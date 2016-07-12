unit FormMacro11CodeU; 

{
Speicher als editierbare Tabelle
Es werden immer 'memcol' Spalten nebeneinander angezeigt
Kopf "+0, +2, +4, ..."
Reihen

Die Anzahl der Spalten wird im Constructor festgelegt ('MemoryColumns').

}

interface 

uses 
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms, 
  Dialogs, Grids, StdCtrls, ExtCtrls, 
  FormChildU, 
  JH_Utilities, 
  AddressU, 
  MemoryCellU, 
  Menus, 
  FrameMemoryCellGroupGridU ; 

type 
  TFormMacro11Code = class(TFormChild) 
      PanelT: TPanel; 
      DepositAllButton: TButton; 
      Label1: TLabel; 
      StartAddrEdit: TEdit; 
      MemoryGrid: TFrameMemoryCellGroupGrid; 

      procedure DepositAllButtonClick(Sender: TObject); 
    private 
      { Private-Deklarationen }
    public 
      { Public-Deklarationen }
      constructor Create(AOwner: TComponent) ; 
      destructor Destroy ; override ; 

      procedure UpdateDisplay(Sender: TObject); 
    end{ "TYPE TFormMacro11Code = class(TFormChild)" } ; 

//var
//  FormMacro11Code: TFormMacro11Code;

implementation 

{$R *.dfm}

uses 
  AuxU, FormMainU; 

  
constructor TFormMacro11Code.Create(AOwner: TComponent) ; 
  begin 
    inherited Create(AOwner) ; 
    MemoryGrid.OnUpdate := UpdateDisplay ; // wenn sich das grid �ndert, muss diese Form reagieren
    StartAddrEdit.ReadOnly := true ; 

  end; 

destructor TFormMacro11Code.Destroy ; 
  begin 
    inherited ; 
  end; 



// neue malen
procedure TFormMacro11Code.UpdateDisplay(Sender: TObject); 
  var 
    mc: TMemoryCell ; 
    h, w: integer ; 
  begin 
    if Sender <> MemoryGrid then // hat der Frame das Update ausgel�st?
      MemoryGrid.UpdateDisplay  // nein: update frame, er updated wieder die Form
    else begin 
      // Editierte Memoryinhalte behalten, auch wenn Pdp durch callbacks neu abgefragt wird.
      MemoryGrid.memorycellgroup.PdpOverwritesEdit := false ; // statische initialisierung

      mc := MemoryGrid.memorycellgroup.Cell(0) ; 
      StartAddrEdit.Text := Addr2OctalStr(mc.addr) ; // 1. Zelle = Startaddr
      Caption := setFormCaptionInfoField(Caption, Addr2OctalStr(mc.addr)) ; 

      // Das MemoryGrid ist alClient und m�chte in einer bestimmten Gr�sse angezeigt werden,
      // tue ihm den Gefallen.
      // Wilde ad hoc Logik: das Codewindow kann extrem hoch werden, dann k�rzer anzeigen
      h := MemoryGrid.optimal_height + PanelT.Height ; 
      w := MemoryGrid.optimal_width ; 
      if h > (FormMain.ClientHeight-100) then 
        h := FormMain.ClientHeight-100  ; 
      if h < 200 then h := 200 ; // falls mainform klein ist
      if h - PanelT.Height < MemoryGrid.optimal_height then 
        w := w + 20 ; // grid zeigt vertical scrollbar

      ClientHeight := h ; 
      ClientWidth := w ; 
    end{ "if Sender <> MemoryGrid ... ELSE" } ; 
  end{ "procedure TFormMacro11Code.UpdateDisplay" } ; 


procedure TFormMacro11Code.DepositAllButtonClick(Sender: TObject); 
  begin 
    MemoryGrid.DepositAllButtonClick(Sender); 
  end; 

end{ "unit FormMacro11CodeU" } . 


