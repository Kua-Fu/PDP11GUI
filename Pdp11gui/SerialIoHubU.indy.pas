unit SerialIoHubU;
{
   Copyright (c) 2016, Joerg Hoppe
   j_hoppe@t-online.de, www.retrocmp.com

   Permission is hereby granted, free of charge, to any person obtaining a
   copy of this software and associated documentation files (the "Software"),
   to deal in the Software without restriction, including without limitation
   the rights to use, copy, modify, merge, publish, distribute, sublicense,
   and/or sell copies of the Software, and to permit persons to whom the
   Software is furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
   JOERG HOPPE BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
   IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}


{
  Handling des seriellen Datenstroms zwischen
  internem Terminal, interner Consol-Logik,
  externem COM-port bzw externem Telner.
          TConnection

 +-------------------------+
 |            TConsole     |
 | API                     |
 |            <-RcvData--  |   Console_WriteData                                   +---------------+
 |<--->                    |                                                       |  physical     |
 |            --XmtData->  |   Console_OnReadData                                  |  Interface    |
 |                         |                                                       |  serial/telnet|
 | <.......busy ...........|                                                       |               |
 +-------------------------+                                                       |               |
 +-------------------------+                                  Physical_Writebyte   | ---------->   |
 |         Terminal        |                                                       |               |
 |         display "grey"  |                                  Physical_ReadByte    |<----------    |
 |Display  <-------RcvData |   Terminal_WriteData                                  | (polled)      |
 |           display       |                                                       +---------------+
 |         <-------------- |
 |                         |
 |         manual typing   |
 |         -----XmtData>   |   Terminal_OnReadByte
 +-------------------------+

// Physikalische Verbindung zu einer PDP-11
// wird von Console* zur Ansteuerung benutzt
// Serials IO �ber COM oder �ber den PDP-11/44-Simulator, oder Telnet
}
interface

uses
  Windows, Classes,
  SysUtils,
  ExtCtrls,
  CommU,
  FakePDP11GenericU,
  FormTerminalU,
  IdTelnet, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient,
  AddressU,
  FormLogU
  ;



type
  // und �ber welches Medium?
  TSerialIoHubPhysicalConnectionType = (connectionNone, connectionInternal, connectionSerial, connectionTelnet) ;


  TSerialIoHub = class(TObject)
    private
      Comm : TComm ; // der COM-Port

      Physical_PollTimer: TTimer ;
      // es darf nicht gepollt werden, w�hrend Zeichen von Console/terminal verarbeitet werden:
      // dauert die Verarbeitung zu lange, wird sonst neu gepollt, und neuere Zeichen werden
      // vor �lteren verarbeitet!
      Transmission_TotalChars: longint ; // soviele Zeichen wurden insgesamt �bertragen
      Transmission_TotalWait_us: int64 ; // soviele microsecs wurde insgasamt geartet

      Telnet_connected : boolean ;
      Telnet_InputBuffer: string ;
      // Telnet Daten da: sammle sie im InputBuffer

      procedure TelnetDataAvailable(Sender: TIdTelnet; const Buffer: TBytes) ;
      procedure TelnetConnect(Sender: TObject) ;
      procedure Physical_Poll(Sender:TObject) ;

    public
      connectionType: TSerialIoHubPhysicalConnectionType ; // Mit was verbinden?
      // wenn intern: IMMER gefakte PDP-11/44!

      IdTelnet: TIdTelnet ;

      isLocalTelnet: boolean ; // true, wenn telnet nach localhost ... fuer locale SimH-Connection

      Console: TObject ; // TConsoleGeneric ;
      Terminal: TformTerminal ;

      FakePDP11: TFakePDP11Generic; // kann 11/44 oder 11/ODT sein

      Physical_Poll_Disable: integer ; // 0 = callback l�uft, sonst nicht.

      // Baudraten, werden f�r jede Verbindung defineirt, f�r timeouts
      RcvBaudrate: integer ;
      XmtBaudrate: integer ;

      constructor Create ;
      destructor Destroy ; override ;

      // Wartepause f�r eine Anzahl von Zeichen, gem�ss Baudrate
      procedure TransmissionWait(charcount: integer) ;
      // Zeit im Millisekuden, die die angegeben Zeichen zahl in Abh
      // von Rcv oder Xmtbaudrate ben�tigt
      function getXmtTransmissionMillis(charcount: integer): integer ;
      function getRcvTransmissionMillis(charcount: integer): integer ;

      ////// Schnittstelle zur Aussenwelt
      // Wahl der Init-Routine bestinmmt Ein/Ausgabeziel
      procedure Physical_InitForCOM(comport: integer ; baud: integer) ;
      procedure Physical_InitForFakePDP11M9312(baud: integer) ;
      procedure Physical_InitForFakePDP1144(baud:integer) ; // baud zum Warten
      procedure Physical_InitForFakePDP11ODT(baud: integer; physicaladdresswidth: TMemoryAddressType) ;
      procedure Physical_InitForTelnet(host:string ; port: integer) ;

      // f�r Anzeigen: "COM1 @ 9600 baud" oder "localhost:9922"
      function Physical_getInfoString: string ;

      // Interface zur Conole-Logic:
      procedure DataToConsole(curdata:string) ; // daten an console
      procedure DataFromConsole(curdata:string) ; // Event: Daten von Consoloe

      // Interface zum Terminal:
      procedure DataToTerminal(curdata:string; style: TTerminalOutputStyle) ; // daten an Terminal
      procedure DataFromTerminal(curdata:string) ; // Event: Daten von Consoloe

      function Physical_ReadByte(var curbyte: byte ; dbglocation: string): boolean ;
      function Physical_WriteByte(curbyte: byte ; dbglocation: string): boolean ;

    end{ "TYPE TSerialIoHub = class(TObject)" } ;


implementation

uses
  JH_Utilities,
  AuxU,
  Forms,
  ConsoleGenericU,
  FakePDP11M9312U,
  FakePDP1144U,
  FakePDP11ODTU,
  FormSettingsU,
  FormMainU ;

//  var dbgsim : TPDP1144Sim ;
var
  loglastlocation:string ;


procedure LogChar(colidx: TLogColumnIndex ; c:char ; location:string) ;
  begin
    if not Connection_LogIoStream then Exit ;

    if location = loglastlocation then // kurzform
      LogStrCol(colidx, Format('%s   "',[CharVisible(c)]))
    else
      LogStrCol(colidx, Format('%s %s', [CharVisible(c), location])) ;
//    if c = #$0d then
//      Flush(logf) ;
    loglastlocation := location;
  end;



constructor TSerialIoHub.Create ;
  begin
    inherited ;
    Comm := TComm.Create(nil);
    FakePDP11 := nil ; // wird erst in Init instanziiert.

    IdTelnet := TIdTelnet.Create ;
    IdTelnet.Name := 'IdTelnet' ;
    IdTelnet.Terminal := 'dumb' ;
    IdTelnet.ThreadedEvent := false ;
    // IdTelnet.Host := ;
    // IdTelnet.Port := ;
    isLocalTelnet := false ;

    Physical_PollTimer := TTimer.Create(nil) ;
    Physical_PollTimer.Interval := 10 ;
    Physical_Poll_Disable := 1 ; // callback abschalten, wird nach Physical_Init...() aktiv

    Physical_PollTimer.Enabled := true ;
    Physical_PollTimer.OnTimer := Physical_Poll ;

  end{ "constructor TSerialIoHub.Create" } ;

destructor TSerialIoHub.Destroy ;
  begin
    Physical_PollTimer.Free ;
    Comm.Free ;
    if FakePDP11 <> nil then FakePDP11.Free ;
    FakePDP11 := nil ;
    IdTelnet.Free ;
    inherited ;
  end;

procedure TSerialIoHub.Physical_InitForCOM(comport: integer ; baud: integer) ;
  begin
    Physical_Poll_Disable := 1 ;
    connectionType := connectionSerial ;

    Comm.Close ;
    Comm.port := comport ;
    Comm.baud := baud ;
    RcvBaudrate := baud ;
    XmtBaudrate := baud ;

    Log('Trying to open COM%d with %d baud ...', [comport, baud]) ;
    Comm.Open ;
    Log('... OK') ;

    Transmission_TotalChars := 0 ;
    Transmission_TotalWait_us:= 0 ;
    Physical_Poll_Disable := 0 ;
  end{ "procedure TSerialIoHub.Physical_InitForCOM" } ;

// baudrate f�r simuliertes Warten
procedure TSerialIoHub.Physical_InitForFakePDP11M9312(baud: integer) ;
  begin
    Physical_Poll_Disable := 1 ;
    connectionType := connectionInternal ;
    RcvBaudrate := baud ;
    XmtBaudrate := baud ;
    // nur freigeben, wenn �nderung, damit die Maschine ihren Zustand m�glichst beh�lt
    if (FakePDP11 = nil) or (FakePDP11.ClassType <> TFakePDP11M9312) then begin
      if FakePDP11 <> nil then FakePDP11.Free ;
      FakePDP11 := TFakePDP11M9312.Create ;
    end;
    Log('Simulated PDP-11 with M9312 console emulator powered ON!') ;
    Physical_Poll_Disable := 0 ;
  end{ "procedure TSerialIoHub.Physical_InitForFakePDP1144" } ;


// baudrate f�r simuliertes Warten
procedure TSerialIoHub.Physical_InitForFakePDP1144(baud: integer) ;
  begin
    Physical_Poll_Disable := 1 ;
    connectionType := connectionInternal ;
    RcvBaudrate := baud ;
    XmtBaudrate := baud ;
    // nur freigeben, wenn �nderng, damit die Maschine ihren Zustand m�glichst beh�lt
    if (FakePDP11 = nil) or (FakePDP11.ClassType <> TFakePDP1144) then begin
      if FakePDP11 <> nil then FakePDP11.Free ;
      FakePDP11 := TFakePDP1144.Create ;
    end;
    Log('Simulated PDP-11/44 powered ON!') ;
    Physical_Poll_Disable := 0 ;
  end{ "procedure TSerialIoHub.Physical_InitForFakePDP1144" } ;

// baudrate f�r simuliertes Warten
procedure TSerialIoHub.Physical_InitForFakePDP11ODT(baud: integer; physicaladdresswidth: TMemoryAddressType) ;
  begin
    Physical_Poll_Disable := 1 ;
    connectionType := connectionInternal ;
    RcvBaudrate := baud ;
    XmtBaudrate := baud ;
    // nur freigeben, wenn �nderung, damit die Maschine ihren Zustand m�glichst beh�lt
    if (FakePDP11 = nil)
            or (FakePDP11.ClassType <> TFakePDP11ODT)
            or (FakePDP11.mat <> physicaladdresswidth)
      then begin
        if FakePDP11 <> nil then FakePDP11.Free ;
        FakePDP11 := TFakePDP11ODT.Create(physicaladdresswidth) ;
      end;
    Log('Simulated PDP-11/ODT %d bit powered ON!', [
            AddrType2Bitswidth(physicaladdresswidth)]) ;
    Physical_Poll_Disable := 0 ;
  end{ "procedure TSerialIoHub.Physical_InitForFakePDP11ODT" } ;

// verbinde �ber Telnet .. damit automatisch SimH ... nicht gerade logisch
procedure TSerialIoHub.Physical_InitForTelnet(host:string ; port: integer) ;
  begin
    Physical_Poll_Disable := 1 ;
    connectionType := connectionTelnet ;


    RcvBaudrate := 9600 ; // das ist minmale Speed von telnet
    XmtBaudrate := 9600 ;


    Telnet_InputBuffer := '' ;
    try
      IdTelnet.Disconnect(true);
    except
      on e: Exception do
    end;
    Telnet_connected := false ;
    IdTelnet.host := host ;
    IdTelnet.port := port ;
    IdTelnet.OnDataAvailable := TelnetDataAvailable ; // callback
    IdTelnet.OnConnected := TelnetConnect ; // callback
    try
      IdTelnet.Connect;

      // ist host der localhost?
      isLocalTelnet := GetIPAddress('localhost') = GetIPAddress(host) ;

    except
      Log('Telnet to "%s" over port %d FAILED!', [host, port]) ;
    end;



    Physical_Poll_Disable := 0 ;
  end{ "procedure TSerialIoHub.Physical_InitForTelnet" } ;


// Zeit im Millisekuden, die die angegeben Zeichen zahl in Abh
// von Rcv oder Xmtbaudrate ben�tigt
function TSerialIoHub.getXmtTransmissionMillis(charcount: integer): integer ;
  begin
    result := charcount * {bits/char} 10 * {ms/sec} 1000 div XmtBaudrate;
  end;

function TSerialIoHub.getRcvTransmissionMillis(charcount: integer): integer ;
  begin
    result := charcount * {bits/char} 10 * {ms/sec} 1000 div RcvBaudrate ;
  end;


// wartet solange, wie die �bertragung von "charcount" Zeichen dauert
// warte NICHT "per char", sondern wartet,so
// das immer die "total transmission time" f�r alle Zeichen bisher
//   stimmt
procedure TSerialIoHub.TransmissionWait(charcount: integer) ;
  var
    planned_Transmission_TotalWait_us: int64 ;
    wait_period_us : int64 ; // solange diesmal warten
    wait_starttime_us: int64 ;
    wait_endtime_us: int64 ;
  begin
    if XmtBaudrate = 0 then // nicht warten
      Exit ;

    Transmission_TotalChars := Transmission_TotalChars + charcount ;
    // �berlauf erst nach 10 Mrd Zeichen
    planned_Transmission_TotalWait_us :=
            int64(1000000) * (Transmission_TotalChars * {bit sper char}10) div XmtBaudrate ;
    // also zu warten?
    wait_period_us := planned_Transmission_TotalWait_us - Transmission_TotalWait_us ;

    // warten mit dem unpr�zisen "sleep(). Messen, wie lange es wirklich dauerte
    QueryPerformanceCounter(wait_starttime_us) ;
    wait_endtime_us := wait_starttime_us ;
    while wait_endtime_us < (wait_starttime_us + wait_period_us) do begin
      Sleep(1) ;
      QueryPerformanceCounter(wait_endtime_us) ;
    end;

    // Tats�chlich insgesamt gewartete Zeit speichern
    Transmission_TotalWait_us := Transmission_TotalWait_us +
            (wait_endtime_us - wait_starttime_us) ;
  end{ "procedure TSerialIoHub.TransmissionWait" } ;


procedure TSerialIoHub.TelnetConnect(Sender: TObject) ;
  begin
    Telnet_connected := true ;
    Log('Telnet to "%s" over port %d OK!', [IdTelnet.host, IdTelnet.port]) ;
  end;

// Telnet Daten da: sammle sie im InputBuffer
procedure TSerialIoHub.TelnetDataAvailable(Sender: TIdTelnet; const Buffer: TBytes);
 var i: integer ;
  begin
  for i:= 0 to length(buffer) - 1 do
    Telnet_InputBuffer := Telnet_InputBuffer + Char(Buffer[i]) ;
  end;


function TSerialIoHub.Physical_ReadByte(var curbyte: byte ; dbglocation: string): boolean ;
  begin
    inc(Physical_Poll_Disable) ; // kein parallellauf
    try
      result := false ;
      case connectionType of
        connectionInternal: begin
          result := FakePDP11.SerialReadbyte(curbyte) ;
          if result then TransmissionWait(1) ;
        end;
        connectionSerial: begin
          result := Comm.ReadByte(curbyte) ;
        end;
        connectionTelnet: begin
          Application.ProcessMessages ; // bediene den Empfangs-Event
//      if not Telnet_Connected then raise Exception.Create('Telnet not connected') ;

          if length(Telnet_InputBuffer) > 0 then begin
            // nimm n�chstes gepuffertes Zeichen
            curbyte := byte(Telnet_InputBuffer[1]) ;
            Telnet_InputBuffer := Copy(Telnet_InputBuffer, 2, maxint) ;
            result := true ;
          end else
            result := false ;
        end;
      end{ "case connectionType" } ;

      // Bis auf weiteres: parity wegschneiden, alle PDP-11 liefern 7 bit chars.
      curbyte := curbyte and $7F ;

      if Connection_LogIoStream and result then
        LogChar(LogCol_PhysicalReadByte, char(curbyte), 'Read.'+dbglocation);
//        Log('Physical_ReadByte:"%s"', [CharVisible(char(curbyte))]) ;

    finally
      dec(Physical_Poll_Disable) ;
    end{ "try" } ;
  end{ "function TSerialIoHub.Physical_ReadByte" } ;


function TSerialIoHub.Physical_WriteByte(curbyte: byte; dbglocation:string): boolean ;
  begin
    inc(Physical_Poll_Disable) ; // kein parallellauf
    try
      if Connection_LogIoStream then
        LogChar(LogCol_PhysicalWriteByte, char(curbyte), 'Write.'+dbglocation);
//        Log('Physical_WriteByte:"%s"', [CharVisible(char(curbyte))]) ;
      result := false ;
      case connectionType of
        connectionInternal: begin
          result := FakePDP11.SerialWriteByte(curbyte) ;
          if result then TransmissionWait(1) ;
        end ;
        connectionSerial: begin
          result := Comm.WriteByte(curbyte) ;
        end;
        connectionTelnet: begin
          // if not Telnet_Connected then  raise Exception.Create('Telnet not connected') ;
          IdTelnet.SendCh(char(curbyte)) ;
          result := true ;
        end;
      end{ "case connectionType" } ;
    finally
      dec(Physical_Poll_Disable) ;
    end{ "try" } ;
  end{ "function TSerialIoHub.Physical_WriteByte" } ;


// wird periodisch aufgerufen, fragt Daten aus seriellem Port ab
// leitet sie an Terminal weiter
procedure TSerialIoHub.Physical_Poll(Sender:TObject) ;
  var buff:string ;
    curbyte: byte ;
  begin
//logstr('TSerialIoHub.Physical_Poll(): Poll_Disable = ' + inttostr(Physical_Poll_Disable)) ;
    if Physical_Poll_Disable > 0 then
      Exit ; // no-op
    buff := '' ;
    while Physical_ReadByte(curbyte, 'IoHub.Poll') do
      buff := buff + char(curbyte) ;
    if buff <> '' then begin
//Log('TSerialIoHub.Physical_Poll: %s', [buff]) ;
      // weiterleiten
      DataToTerminal(buff, tosPDP);
      DataToConsole(buff);
    end;
  end{ "procedure TSerialIoHub.Physical_Poll" } ;


// f�r Anzeigen: "COM1 @ 9600 baud" oder "localhost:9922"
function TSerialIoHub.Physical_getInfoString: string ;
  begin
    result := 'unknown Connection' ;
    case connectionType of
      connectionInternal:
        result := 'internal connection' ;
      connectionSerial:
        result := Format('COM%d @ %d baud', [Comm.port, Comm.baud]) ;
      connectionTelnet:
        result := Format('%s:%d', [IdTelnet.host, IdTelnet.port]) ;
    end;
  end;


// daten an console weiterleiten
procedure TSerialIoHub.DataToConsole(curdata:string) ;
  begin
    // nicht pollen, wenn Daten gerade von Console/Terminal verarbeitet werden.
    inc(Physical_Poll_Disable) ; // kein Parallellauf
    try
      assert(Console <> nil) ;
      (Console as TConsoleGeneric).OnSerialRcv(curdata) ;
    finally
      dec(Physical_Poll_Disable);
    end;
  end;

// wird von Console aufgerufen, wenn die Daten schreiben will
procedure TSerialIoHub.DataFromConsole(curdata:string) ; // Event: Daten von Consoloe
  var i: integer ;
  begin
    // nicht pollen, wenn Daten gerade von Console/Terminal verarbeitet werden.
    inc(Physical_Poll_Disable) ; // kein Parallellauf
    try
      for i := 1 to length(curdata) do
        Physical_WriteByte(byte(curdata[i]), 'IoHubDataFromConsole') ;
//    DataToTerminal(curdata, tosPDP) ; // daten auch auf Terminal anzeigen in adnerer Farbe
    finally
      dec(Physical_Poll_Disable);
    end;
  end;


// Interface zum Terminal:
procedure TSerialIoHub.DataToTerminal(curdata:string; style: TTerminalOutputStyle) ; // daten an Terminal
  begin
    // nicht pollen, wenn Daten gerade von Console/Terminal verarbeitet werden.
    inc(Physical_Poll_Disable) ; // kein Parallellauf
    try
      assert(Terminal <> nil) ;
//if pos('{', curdata) > 0 then
// curdata := curdata +'#' ; // break here
      Terminal.OnSerialRcvData(curdata) ;
    finally
      dec(Physical_Poll_Disable);
    end;
  end;


// wird von Terminal aufgerufen, wenn es Daten schreiben will
// (= wenn der User was getippt hat)
procedure TSerialIoHub.DataFromTerminal(curdata:string) ; // Event: Daten von Consoloe
  var i: integer ;
  begin
    // nicht pollen, wenn Daten gerade von Console/Terminal verarbeitet werden.
    inc(Physical_Poll_Disable) ; // kein Parallellauf
    try
      assert(Console <> nil) ;
      // nur an den physical port ausgeben, wenn der nicht von der Console belegt ist.
      if not (Console as TConsoleGeneric).InCriticalSection then
        for i := 1 to length(curdata) do
          Physical_WriteByte(byte(curdata[i]), 'IoHubDataFromTerminal') ;
    finally
      dec(Physical_Poll_Disable);
    end;
  end{ "procedure TSerialIoHub.DataFromTerminal" } ;


initialization
      loglastlocation := '' ;



end{ "unit SerialIoHubU" } .
