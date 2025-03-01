{******************************************************************************}
{                                                                              }
{       Ghostscript API Wrapper: An extended Ghostscript API for Delphi        }
{       to simplify use of Ghostscript.                                        }
{                                                                              }
{       Copyright (c) 2021-2022 (Ski-Systems)                                  }
{       Author: Jan Blumstengel                                                }
{                                                                              }
{       https://github.com/SKI-Systems/Ghostscript-API-Wrapper                 }
{                                                                              }
{******************************************************************************}
{                                                                              }
{    This program is free software: you can redistribute it and/or modify      }
{    it under the terms of the GNU Affero General Public License as            }
{    published by the Free Software Foundation, either version 3 of the        }
{    License, or (at your option) any later version.                           }
{                                                                              }
{    This program is distributed in the hope that it will be useful,           }
{    but WITHOUT ANY WARRANTY; without even the implied warranty of            }
{    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             }
{    GNU Affero General Public License for more details.                       }
{                                                                              }
{    You should have received a copy of the GNU Affero General Public License  }
{    along with this program.  If not, see <https://www.gnu.org/licenses/>.    }
{                                                                              }
{******************************************************************************}

unit Main;

interface

uses
  SkiSys.GS_Api, SkiSys.GS_Converter, SkiSys.GS_ParameterConst,

  SysUtils, Variants, Classes, Controls, Forms, LCLProc,
  Dialogs, StdCtrls, Buttons, ExtCtrls, IniFiles, ComCtrls, Graphics
  {$IFDEF MSWINDOWS}
  , Windows
  {$ENDIF}
  ;

type

  { TFMain }

  TFMain = class(TForm)
    Btn_Convert: TButton;
    Img_Page: TImage;
    LEd_File: TLabeledEdit;
    LEd_PageCount: TLabeledEdit;
    M_Errors: TMemo;
    M_Output: TMemo;
    M_UserParams: TMemo;
    OpenDialog: TOpenDialog;
    Pages: TPageControl;
    P_Client: TPanel;
    P_PreviewTop: TPanel;
    P_Top: TPanel;
    RGrp_Devices: TRadioGroup;
    SBtn_OpenFile: TSpeedButton;
    ScrollBox1: TScrollBox;
    Splitter1: TSplitter;
    Splitter_Top: TSplitter;
    Tab_Operation: TTabSheet;
    Tab_PdfView: TTabSheet;
    procedure Btn_ConvertClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure SBtn_OpenFileClick(Sender: TObject);
    procedure UpDown_PagesClick(Sender: TObject; Button: TUDBtnType);
  private
    FCurrentPage: Integer;
    PDFConvert: TGS_PdfConverter;
    GSDllDir: string;
    ICCProfileDir: string;
    Ini: TIniFile;
    procedure AfterExecute(Sender: TObject);
    function GetOutputDir(ADir, AName: string): string;
    procedure ReadIni;
    procedure SetCursorToEnd(AMemo: TMemo);
    procedure SetPage(APage: Integer);
    procedure SetPreview;
    procedure StdError(const AText: string);
    procedure StdIn(const AText: string);
    procedure StdOut(const AText: string);
  protected
    procedure Convert;
    procedure Convert_DisplayPdf(SearchDir, InputFile: string; UseThread: Boolean);
    procedure Convert_DisplayPdfA(SearchDir, AICCProfileDir, InputFile: string; UseThread: Boolean);
    procedure Convert_WritePdf(SearchDir, InputFile: string; UseThread: Boolean);
    procedure Convert_WritePdfA(SearchDir, AICCProfileDir, InputFile: string; UseThread: Boolean);
  public
    { Public-Deklarationen }
  end;

var
  FMain: TFMain;

implementation

{$R *.lfm}

procedure TFMain.AfterExecute(Sender: TObject);
begin
  Screen.Cursor := crDefault;
  if (PDFConvert.LastErrorCode < 0) then
    MessageDlg(PDFConvert.LastErrors, mtError, [mbOK], 0);
  Btn_Convert.Enabled := True;
  SetPage(0);
  // Show the Preview, if created -> only availible with Device := 'display'
  if (RGrp_Devices.ItemIndex in [0, 1]) and (PDFConvert.LastErrorCode = 0) then
    Pages.ActivePage := Tab_PDFView;
end;

procedure TFMain.Btn_ConvertClick(Sender: TObject);
begin
  Convert;
end;

procedure TFMain.FormCreate(Sender: TObject);
var
  ADir: string;
begin
  ReadIni;
  ADir := GSDllDir;
  if (not DirectoryExists(ADir)) then
    ADir := '';

  //fix an issue with the speed button on different platforms
  {$IFDEF MSWINDOWS}SBtn_OpenFile.Top := LEd_File.Top - 2{$ENDIF};

  // create an API Converter instance
  PDFConvert := TGS_PdfConverter.Create(ADir);
  // set the events for the Ghostscript and Wrapper output
  PDFConvert.OnAfterExecute := @AfterExecute;
  PDFConvert.OnStdError := StdError;
  PDFConvert.OnStdIn := StdIn;
  PDFConvert.OnStdOut := StdOut;
  // When you don't want to use the events, you can use the Log instead
  //PDFConvert.LastErrors;
  //PDFConvert.StdInLog;
  //PDFConvert.StdOutLog;

  Pages.ActivePage := Tab_Operation;
  FCurrentPage := 0;
  SetPreview;
end;

procedure TFMain.FormDestroy(Sender: TObject);
begin
  if (Ini <> nil) then
  begin
    Ini.WriteString('Path', 'LastFile', LEd_File.Text);
    Ini.WriteString('Path', 'GS_DLL_Path', GSDllDir);
    Ini.WriteString('Path', 'ICCProfileDir', ICCProfileDir);
    Ini.WriteString('User', 'Params', M_UserParams.Lines.Text.Replace(#13#10, '*#*'));
    Ini.WriteInteger('User', 'ConvertDevice', RGrp_Devices.ItemIndex);
    FreeAndNil(Ini);
  end;
  FreeAndNil(PDFConvert);
end;

function TFMain.GetOutputDir(ADir, AName: string): string;
begin
  Result := ADir + AName + PathDelim;
  if (not DirectoryExists(Result)) then
    CreateDir(Result);
end;

procedure TFMain.ReadIni;
const
  DefaultLib = '..' + PathDelim + '..' + PathDelim + 'bin';
  DefaultICCProfiles = '..' + PathDelim + '..' + PathDelim + 'ICC-Profiles';
var
  AFile: string;
begin
  // read stored user informations from the ini file
  AFile := ChangeFileExt(Application.ExeName, '.ini');
  Ini := TIniFile.Create(AFile);
  GSDllDir := Ini.ReadString('Path', 'GS_DLL_Path', DefaultLib);
  ICCProfileDir := Ini.ReadString('Path', 'ICCProfileDir', DefaultICCProfiles);
  LEd_File.Text := Ini.ReadString('Path', 'LastFile', '');
  M_UserParams.Lines.Text := Ini.ReadString('User', 'Params', '').Replace('*#*', #13#10);
  RGrp_Devices.ItemIndex := Ini.ReadInteger('User', 'ConvertDevice', 0);
end;

procedure TFMain.SBtn_OpenFileClick(Sender: TObject);
begin
  if (OpenDialog.Execute) then
    LEd_File.Text := OpenDialog.FileName;
end;

procedure TFMain.SetCursorToEnd(AMemo: TMemo);
begin
  // set the cursor at the end of the memo (auto scroll)
  with AMemo do
  begin
    SelStart := Length(Text);
    SelLength := 0;
    {$IFDEF MSWINDOWS}Perform(EM_SCROLLCARET, 0, 0);{$ENDIF}
  end;
end;

procedure TFMain.SetPage(APage: Integer);
var
  ABmp: TGS_Image;
begin
  // get a page image preview (only performed with Device='display')
  if (PDFConvert.GSDisplay.PageCount > 0) and (PDFConvert.GSDisplay.PageCount > APage) then
  begin
    ABmp := PDFConvert.GSDisplay.GetPage(APage);
    if (ABmp <> nil) then
    begin
      Img_Page.Picture.Assign(ABmp);
      Img_Page.Width := ABmp.Width;
      Img_Page.Height := ABmp.Height;
      FCurrentPage := APage;
      SetPreview;
    end;
  end;
end;

procedure TFMain.SetPreview;
var
  ShownPage: Integer;
begin
  ShownPage := 0;
  if (PDFConvert.GSDisplay.PageCount > 0) then
    ShownPage := FCurrentPage + 1;
  LEd_PageCount.Text := Format('%d/%d', [ShownPage, PDFConvert.GSDisplay.PageCount]);
end;

procedure TFMain.StdError(const AText: string);
begin
  //write the Ghostscript errors and API messages in a TMemo
  M_Errors.Text := M_Errors.Text + AText;
  SetCursorToEnd(M_Errors);
end;

procedure TFMain.StdIn(const AText: string);
begin
  M_Output.Lines.Add('IN: ' + AText);
end;

procedure TFMain.StdOut(const AText: string);
begin
  //write the Ghostscript output in a TMemo
  M_Output.Text := M_Output.Text + AText;
  SetCursorToEnd(M_Output);
end;

procedure TFMain.Convert;
var
  ADir, AFile, AProfileDir: string;
  AThread: Boolean;
begin
  Btn_Convert.Enabled := False;
  Screen.Cursor := crHourGlass;
  AFile := LEd_File.Text;
  AThread := True; // run it in a thread to prevent the gui from freezing

  try
    if (not FileExists(AFile)) then
      raise EFileNotFoundException.CreateFmt('The file: %s does not exist', [AFile]);

    ADir := ExtractFilePath(ParamStr(0));
    AProfileDir := ICCProfileDir;
    if (not AProfileDir.EndsWith(PathDelim)) then
      AProfileDir := AProfileDir + PathDelim;

{$IFDEF DEBUG}
    (* You can set different debug options for th API *)

    // shows the parameters and other informations in the OnStdOut
    PDFConvert.Debug := True;
    // shows the used parameters as cmd args
    PDFConvert.DebugShowCmdArgs := True;

    // shows the communictaion of Ghostscript with API, if you use
    PDFConvert.GSDisplay.Debug := True;

    // debug options for Ghostscript
    PDFConvert.DebugParams.DebugParams :=
      [dparCompiledFonts, dparCffFonts,
      dparCIEColor, dparFontApi, dparTTFFonts, dparInitialization];

{$ENDIF}
    // set a title for the PDF-File
    // when a title allready exists this param will be ignored
    PDFConvert.Params.PdfTitle := 'GS Example Title';

    case RGrp_Devices.ItemIndex of
      0: Convert_DisplayPdf(ADir, AFile, AThread);
      1: Convert_DisplayPdfA(ADir, AProfileDir, AFile, AThread);
      2: Convert_WritePdf(ADir, AFile, AThread);
      3: Convert_WritePdfA(ADir, AProfileDir, AFile, AThread);
      else raise Exception.Create('No Convert Device selected');
    end;

  except
    on E: Exception do begin
      AfterExecute(PDFConvert);
      MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TFMain.Convert_DisplayPdf(SearchDir, InputFile: string;
  UseThread: Boolean);
var
  OutputDir: string;
begin
  OutputDir := GetOutputDir(SearchDir, 'pdf');

  // Device -> display is set as a device so we can not use ColorConversionStrategy
  PDFConvert.Params.Device := DISPLAY_DEVICE_NAME; // show pdf when finished
  PDFConvert.UserParams.Clear;
  // add the parameters from the Memo
  PDFConvert.UserParams.AddStrings(M_UserParams.Lines);
  PDFConvert.ToPdf(InputFile, OutputDir + ChangeFileExt(ExtractFileName(InputFile), '.pdf'), UseThread);
end;

procedure TFMain.Convert_DisplayPdfA(SearchDir, AICCProfileDir, InputFile: string;
  UseThread: Boolean);
var
  OutputDir: string;
begin
  OutputDir := GetOutputDir(SearchDir, 'pdfa');

  PDFConvert.Params.SubsetFonts := False;
  PDFConvert.Params.EmbededFonts := True;
  PDFConvert.Params.ICCProfile := AICCProfileDir + 'default_cmyk.icc';
  PDFConvert.Params.PDFAOutputConditionIdentifier := 'CMYK';
  // Device -> display is set as a device so we can not use ColorConversionStrategy or if set it will be ignored
  PDFConvert.Params.ColorConversionStrategy := ccsCMYK;
  PDFConvert.Params.Device := DISPLAY_DEVICE_NAME; // show pdf when finished -> there will be no output file
  PDFConvert.UserParams.Clear;
  // add the user parameters from the Memo
  PDFConvert.UserParams.AddStrings(M_UserParams.Lines);
  // start the convert operation
  PDFConvert.ToPdfa(InputFile, OutputDir + ChangeFileExt(ExtractFileName(InputFile), '.pdf'), UseThread);
end;

procedure TFMain.Convert_WritePdf(SearchDir, InputFile: string; UseThread: Boolean);
var
  OutputDir, AName: string;
begin
  AName := 'pdf';
  OutputDir := GetOutputDir(SearchDir, AName);

  // Device-> pdfwrite
  PDFConvert.Params.Device := DEVICES_HIGH_LEVEL[pdfwrite];
  PDFConvert.Params.ColorConversionStrategy := ccsRGB;
  PDFConvert.UserParams.Clear;
  // user param example you can add every gs param in default form with the user params
  PDFConvert.UserParams.Add('-sProcessColorModel=DeviceRGB');
  PDFConvert.UserParams.AddStrings(M_UserParams.Lines);
  PDFConvert.ToPdf(InputFile, OutputDir + ChangeFileExt(ExtractFileName(InputFile), '.' + AName), UseThread);
end;

procedure TFMain.Convert_WritePdfA(SearchDir, AICCProfileDir, InputFile: string;
  UseThread: Boolean);
var
  OutputDir: string;
begin
  OutputDir := GetOutputDir(SearchDir, 'pdfa');

  PDFConvert.Params.SubsetFonts := False;
  PDFConvert.Params.EmbededFonts := True;
  // We can convert the file with a different color we have to set both settings.
  // When you make your own PDFA_def.ps you can define it directly in the
  // definition file
  PDFConvert.Params.ICCProfile := AICCProfileDir + 'default_cmyk.icc';
  PDFConvert.Params.PDFAOutputConditionIdentifier := 'CMYK';
  // Device-> pdfwrite
  PDFConvert.Params.Device := DEVICES_HIGH_LEVEL[pdfwrite];
  PDFConvert.Params.ColorConversionStrategy := ccsCMYK;
  PDFConvert.UserParams.Clear;
  PDFConvert.UserParams.Add('-sProcessColorModel=DeviceCMYK');
  PDFConvert.UserParams.AddStrings(M_UserParams.Lines);
  PDFConvert.ToPdfa(InputFile, OutputDir + ChangeFileExt(ExtractFileName(InputFile), '.pdf'), UseThread);
end;

procedure TFMain.UpDown_PagesClick(Sender: TObject; Button: TUDBtnType);
begin
  case Button of
    btNext: SetPage(FCurrentPage + 1);
    btPrev: SetPage(FCurrentPage - 1);
  end;
end;

end.
