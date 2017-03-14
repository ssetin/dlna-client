{********************************************************************}
{                                                                    }
{       MediaServer Runtime Component Library                        }
{       TMediaServer                                                 }
{                                                                    }
{       Implements interaction with media services, based on         }
{       UpnP\DLNA protocols:                                         }
{       - AVTransport v.1                                            }
{                                                                    }
{       Copyright (c) 2014 Setin Sergey A                            }
{                                                                    }
{       v0.5 31.10.2014                                              }
{                                                                    }
{********************************************************************}

unit MediaServer;

interface

uses IdHTTP,Generics.Collections,Classes,Sysutils,XmlDoc,XMLIntf,IdURI,IdLogEvent,IoUtils,Variants,IdExceptionCore,
  IdUDPClient,IdUDPBase,IdStack
  {$IF DEFINED(ANDROID)}, Androidapi.JNIBridge, Androidapi.Jni,Androidapi.NativeActivity,Androidapi.JNI.Net.Wifi,androidapi.JNI.JavaTypes{$ENDIF}
  {$IF DEFINED(MSWINDOWS)},System.Win.ComObj{$ENDIF};


type
  TTransportState = (STOPPED,PLAYING,TRANSITIONING,PAUSED_PLAYBACK,PAUSED_RECORDING,RECORDING,NO_MEDIA_PRESENT);
  TCurrentPlayMode = (NORMAL,SHUFFLE,REPEAT_ONE,REPEAT_ALL,RANDOM,DIRECT_1,INTRO);
  TTransportStatus = (OK,ERROR_OCCURRED);

{
   TActionResult - response from service
}
   TActionResult = class
   public
     XMLDoc: IXMLDocument;
     constructor Create(var xml:TStringStream);
     destructor Destroy; override;
   end;

{
   TActionError - error response
}
   TActionError = class(TActionResult)
   public
     ErrorText:string;
     ErrorCode:string;
     constructor Create(var xml:TStringStream);
   end;

{
   TMediaService - base MediaService class
}
  TMediaService = class
    LogEvent:TIDLogEvent;
    LogList:TStringList;
    procedure IdLogEventReceived(ASender: TComponent; const AText, AData: string);
    procedure IdLogEventSent(ASender: TComponent; const AText,  AData: string);
    function SendRequest(method:string;var cmd:tstringlist;var response:TStringStream):boolean;
  public
    serviceType:string;
    servicekind:string;
    serviceId:string;
    SCPDURL:string;
    controlURL:string;
    baseURL:string;
    eventSubURL:string;
    actionresult:string;
    z_host:string;
    z_port:integer;
    constructor Create(islogged:boolean);
    destructor Destroy; override;
  end;

{
   TMediaAVService - implements urn:schemas-upnp-org:service:AVTransport
}
  TMediaAVService = class(TMediaService)
    //states
    TransportState:TTransportState;
    TransportStatus:string;
    TransportPlaySpeed:string;
    CurrentPlayMode:TCurrentPlayMode;
    CurrentTrackMetaData:string;
    CurrentTrackURI:string;
    AVTransportURI:string;
    AbsoluteTimePosition:string;
    RelativeTimePosition:string;
  public
    constructor Create(islogged:boolean);
    //functions
    function SetAVTransportURI(url:string):TActionResult;
    function Stop:TActionResult;
    function Play:TActionResult;
    function GetMediaInfo:TActionResult;
  end;

{
   TMediaContentDirectoryService - implements urn:schemas-upnp-org:service:ContentDirectory
}
  TMediaContentDirectoryService = class(TMediaService)
    //states
  public
    constructor Create(islogged:boolean);
    //functions
    function Browse(ObjectID:string;BrowseFlag:string;Filter:string;StartingIndex:string;RequestedCount:string;
      SortCriteria:string;var NumberReturned:UINT64;var TotalMatches:UINT64;var UpdateID:UINT64):TActionResult;
  end;

{
   TMediaConnectionManagerService - implements urn:schemas-upnp-org:service:ConnectionManager
}
  TMediaConnectionManagerService = class(TMediaService)
    //states
  public
    constructor Create(islogged:boolean);
    //functions
    function GetProtocolInfo:TActionResult;
  end;

{
   TMediaServer - "link" to server (actually client)
}
  TMediaServer = class
  public
     IP:string;
     PORT:string;
     Modelname:string;
     Location:string;
     BaseLocation:string;
     Logo:string;
     DeviceType:string;
     Manufacturer:string;
     FriendlyName:string;
     LogoType:string;
     ModelDescription:string;
     HomePath:string;
     LogService:boolean;
     ServiceList:TObjectList<TMediaService>;
     constructor Create(cIP: String; cPORT:string; cLocation:string; cHomePath:string);
     destructor Destroy; override;
     procedure LoadDescription;
     function FindService(st:string):TMediaService;
     function GetServiceCount:integer;
  end;

  type TMediaServersList =  TObjectList<TMediaServer>;
  type TOnSearchResult = procedure(serverslist:TMediaServersList) of object;
  type TOnSearchError = procedure(errortxt:string) of object;

{
   TMediaSearch - searcher of the available media services
}
type
  TMediaSearch = class
  protected
     type TSThread = class(TThread)
       IPMASK,PORT,upnpmask:string;
       {$IF DEFINED(ANDROID)}
          wifi_manager:JWifiManager;
          multiCastLock:JWifiManagerMulticastLock;
       {$ENDIF}
       lasterror:string;
       ResultList:TMediaServersList;
       FOnSearchResult: TOnSearchResult;
       FOnSearchError: TOnSearchError;
       procedure SendResult;
       procedure SendError;
       function InitMulticast:boolean;
       function UnInitMulticast:boolean;
       procedure DettachCurrentThreadFromJVM;
     protected
       procedure SetErrorText(msg:string);
     public
       constructor Create(ipm:string;portm:string);
       destructor Destroy; override;
       procedure Execute; override;
       procedure SetSearchMask(upnp_mask:string);
       procedure SetResultEvent(ResultEvent:TOnSearchResult);
       procedure SetErrorEvent(ErrorEvent:TOnSearchError);
     end;
  protected
     SearchThread: TSThread;
  public
     Constructor Create(ipm:string;portm:string);
     destructor Destroy;override;
     procedure Search(upnpmask:string);
     procedure SetResultEvent(ResultEvent:TOnSearchResult);
     procedure SetErrorEvent(ErrorEvent:TOnSearchError);
  end;

{
   Helpers
}
function DownloadFile(url:string;saveto:string):boolean;
function ReadParam(str: string; tagb: string; tage: string; tp: string): string;

implementation

function ReadParam(str: string; tagb: string; tage: string;  tp: string): string;
var
  buf,tmp: String;
  a, b: integer;
begin
  Result := '';
  if tp = 'xml' then
  begin
    a := str.IndexOf(tagb) + length(tagb);
    tmp:= str.Substring(a , length(str) - a);
    b := tmp.IndexOf(tage);
    if (a > High(tagb)) and (b > 1) then
    begin
      Result := trim(str.Substring(a, b));
    end;
  end
  else
  begin
    buf:=str.UpperCase(str);
    a := buf.IndexOf(tagb) + length(tagb);
    tmp:=buf.Substring(a , length(buf) - a);
    b := tmp.IndexOf(tage);
    if (a > High(tagb)) and (b > 1) then
    begin
      Result := trim(str.Substring(a, b));
    end;
  end;
end;

{     TMediaSearch.TSThread     }
constructor TMediaSearch.TSThread.Create(ipm:string;portm:string);
begin
  inherited Create(true);
  FreeOnTerminate:=true;
  IPMASK := ipm;
  PORT := portm;
  lasterror:='';
  {$IF DEFINED(ANDROID)}
    wifi_manager:=nil;
    multiCastLock:=nil;
  {$ENDIF}
end;

destructor TMediaSearch.TSThread.Destroy;
begin
  inherited;
end;

procedure TMediaSearch.TSThread.SetSearchMask(upnp_mask:string);
begin
  upnpmask:=upnp_mask;
end;

procedure TMediaSearch.TSThread.SetErrorText(msg:string);
begin
  lasterror:=msg;
end;

procedure TMediaSearch.TSThread.SetResultEvent(ResultEvent:TOnSearchResult);
begin
  FOnSearchResult:=ResultEvent;
end;

procedure TMediaSearch.TSThread.SetErrorEvent(ErrorEvent:TOnSearchError);
begin
  FOnSearchError:=ErrorEvent;
end;

procedure TMediaSearch.SetResultEvent(ResultEvent:TOnSearchResult);
begin
  SearchThread.SetResultEvent(ResultEvent);
end;

procedure TMediaSearch.SetErrorEvent(ErrorEvent:TOnSearchError);
begin
  SearchThread.SetErrorEvent(ErrorEvent);
end;

procedure TMediaSearch.TSThread.SendResult;
begin
   FOnSearchResult(ResultList);
end;

procedure TMediaSearch.TSThread.SendError;
begin
   FOnSearchError(lasterror);
end;

function TMediaSearch.TSThread.InitMulticast:boolean;
begin
  Result:=true;
  {$IF DEFINED(ANDROID)}
  try
    wifi_manager:=GetWiFiManager;
    if assigned(wifi_manager) then
    begin
      multiCastLock := wifi_manager.createMulticastLock(StringToJString('mservlock'));
      multiCastLock.setReferenceCounted(true);
      multiCastLock.acquire;
    end;
  except
    on E:Exception do
    begin
       Result:=false;
       lasterror:=E.Message;
       if assigned(FOnSearchError) then
          Synchronize(SendError);
    end;
  end;
  {$ENDIF}

end;

function TMediaSearch.TSThread.UnInitMulticast:boolean;
begin
  {$IF DEFINED(ANDROID)}
    if assigned(multiCastLock)then
      multiCastLock.release;
    multiCastLock:=nil;
    wifi_manager:=nil;
  {$ENDIF}
end;

procedure TMediaSearch.TSThread.DettachCurrentThreadFromJVM;
{$IF DEFINED(ANDROID)}
var
  PActivity: PANativeActivity;
  JNIEnvRes: PJNIEnv;
{$ENDIF}
begin
{$IF DEFINED(ANDROID)}
  JNIEnvRes := TJNIResolver.JNIEnvRes;

  if JNIEnvRes <> nil then
  begin
    PActivity := PANativeActivity(System.DelphiActivity);
    PActivity^.vm^.DetachCurrentThread(PActivity^.vm);
    TJNIResolver.JNIEnvRes := nil;
  end;
{$ENDIF}
end;

procedure TMediaSearch.TSThread.Execute;
var S: TStringList;
    U: TIdUDPClient;
    iPeerPort: Word;
    sPeerIP, sResponse, url: string;
    str:TStringList;
    ms:TMediaServer;
    tmppath:string;
begin
  inherited;
  if terminated then exit;

  sPeerIP:='';
  sResponse:='';
  url:='';

  {$IF DEFINED(MSWINDOWS)}
    CoInitializeEx(nil, 0);
  {$ENDIF}

  if not InitMulticast then exit;

  ResultList:=TMediaServersList.Create(true);

  tmppath:=TPath.GetTempPath;
  str:=tstringlist.Create;

  U := TIdUDPClient.Create;
  S := TStringList.Create;
  S.LineBreak:=#13#10;
  str.LineBreak:=#13;

  try
    S.Add('M-SEARCH * HTTP/1.1');
    S.Add('HOST: '+IPMASK+':'+PORT);
    S.Add('MAN: "ssdp:discover"');
    S.Add('MX: 4');
    S.Add('ST: '+upnpmask);
    S.Add('USER-AGENT: OS/1 UPnP/1.1 TMediaServer/1.0');
    S.Add('');

    U.ReceiveTimeout:=5000;

    U.Send(IPMASK, StrToInt(PORT), S.Text);

    repeat
      sResponse := U.ReceiveString(sPeerIP, iPeerPort);
      if iPeerPort <> 0 then begin
        str.Clear;
        str.Text:=sResponse;
        url:=ReadParam(str.Text,'LOCATION:',#13,'http');
        if url>'-' then
        begin
          ms:=TMediaServer.Create(sPeerIP,inttostr(iPeerPort),url,tmppath);
          ms.LoadDescription;
          ResultList.Add(ms);
        end;
      end;
    until iPeerPort = 0;
    S.Free;
    U.Free;
  except
    on et:EIdConnectTimeout do
    begin
      S.Free;
      U.Free;
      lasterror:='Connection error';
      if assigned(FOnSearchError) then
         Synchronize(SendError);
    end;
    on E:Exception do
    begin
      S.Free;
      U.Free;
      lasterror:=E.Message;
      if assigned(FOnSearchError) then
         Synchronize(SendError);
    end;
  end;
  str.Free;

  //CoUninitialize;

  UnInitMulticast;

  if assigned(FOnSearchResult) then
     Synchronize(SendResult);

  {$IF DEFINED(ANDROID)}
    DettachCurrentThreadFromJVM;
  {$ENDIF}

end;

{     TMediaSearch     }
Constructor TMediaSearch.Create(ipm:string;portm:string);
begin
  SearchThread:=TSThread.Create(ipm,portm);
end;

destructor TMediaSearch.Destroy;
begin
  if assigned(SearchThread) then
  begin
     SearchThread.Terminate;
  end;
  inherited;
end;

procedure TMediaSearch.Search(upnpmask:string);
begin
  if not SearchThread.Started then
  begin
   SearchThread.SetSearchMask(upnpmask);
   SearchThread.Start;
  end else
  begin
     //SearchThread.Synchronize(SearchThread.SendError);
  end;
end;


{     TActionResult     }
constructor TActionResult.Create(var xml:TstringStream);
begin
   XMLDoc:=TXMLDocument.Create(nil);
   XMLDoc.LoadFromStream(xml);
end;


destructor TActionResult.Destroy;
begin
//   if assigned(XMLDoc) then
//      XMLDoc.Free;
end;


{     TActionError     }
constructor TActionError.Create(var xml:TstringStream);
var
  Node:IXMLNode;
  got:boolean;
begin
   inherited Create(xml);
   got:=false;
   try
      Node:=XMLDoc.DocumentElement.ChildNodes['Body'].ChildNodes['Fault'];
      Node:=Node.ChildNodes.FindNode('detail','');
      if Node.HasChildNodes then
      begin
        Node:=Node.ChildNodes['UPnPError'];
        if Node.HasChildNodes then
        begin
           Self.ErrorText:=Node.ChildNodes['errorDescription'].Text;
           Self.ErrorCode:=Node.ChildNodes['errorCode'].Text;
           got:=true;
        end;
      end;
   except
      Self.ErrorText:='Unknown error, sorry';
      Self.ErrorCode:='-1';
      got:=true;
   end;

   if not got then
   begin
      Self.ErrorText:=XmlDoc.XML.Text;
      Self.ErrorCode:='-1';
   end;
end;



{     TMediaContentDirectoryService     }
constructor TMediaService.Create(islogged:boolean);
begin
   servicekind:='not implemented';
   //create log
   if (islogged) then
   begin
      LogEvent:=TIDLogEvent.Create;
      LogList:=TStringList.Create;
      LogEvent.ReplaceCRLF:=false;
      LogEvent.OnReceived:=IdLogEventReceived;
      LogEvent.OnSent:=IdLogEventSent;
   end;
end;

procedure TMediaService.IdLogEventReceived(ASender: TComponent; const AText,  AData: string);
begin
  if assigned(LogList)then
  begin
     LogList.Add('Received:');
     LogList.Add(AData);
     LogList.Add('');
  end;
end;

procedure TMediaService.IdLogEventSent(ASender: TComponent; const AText,  AData: string);
begin
  if assigned(LogList)then
  begin
     LogList.Add('Sent:');
     LogList.Add(AData);
     LogList.Add('');
  end;
end;

function TMediaService.SendRequest(method:string;var cmd:tstringlist;var response:TStringStream):boolean;
var
  http:TIDHttp;
  noterr:boolean;
begin
  http:=TIDHttp.Create;
  noterr:=true;

  if Assigned(LogEvent) then
  begin
     http.Intercept:=LogEvent;
     LogEvent.Active:=true;
  end;

  try
     http.Request.Clear;
     http.HTTPOptions:=[hoKeepOrigProtocol];
     http.Request.URL:=controlURL;
     http.Request.ContentType := 'text/xml; charset=utf-8';
     http.ProtocolVersion := pv1_1;
     http.Request.UserAgent:='TMediaServer v1.0';
     http.Request.CustomHeaders.Clear;
     http.Request.CustomHeaders.AddValue('SOAPAction','"'+method+'"');
     http.Post(baseUrl+controlURL,cmd,response);
  except
     on e:EIdHTTPProtocolException do
     begin
       response.Free;
       response:=TstringStream.Create(E.ErrorMessage);
       noterr:=false;
     end;
     on e:Exception do
     begin
       noterr:=false;
       response:=tstringstream.Create('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '+
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'+
          '<s:Body>'+
          '<s:Fault>'+
          '<faultcode>s:Client</faultcode>'+
          '<faultstring>UPnPError</faultstring>'+
          '<detail>'+
          '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'+
          '<errorCode>General Error</errorCode>'+
          '<errorDescription>'+e.Message+'</errorDescription>'+
          '</UPnPError>'+
          '</detail>'+
          '</s:Fault>'+
          '</s:Body>'+
          '</s:Envelope>');
     end;
  end;

  Result:=noterr;

  if Assigned(LogEvent) then
  begin
     LogEvent.Active:=false;
  end;

  http.Free;
end;

destructor TMediaService.Destroy;
begin
  if assigned(LogEvent) then
  begin
    LogEvent.Free;
  end;
  if assigned(LogList) then
  begin
    LogList.SaveToFile(Tpath.Combine(TPath.GetTempPath,servicekind+'.log'));
    LogList.Free;
  end;
  inherited;
end;

{     TMediaConnectionManagerService     }
constructor TMediaConnectionManagerService.Create(islogged:boolean);
begin
  inherited Create(islogged);
  servicekind:='ConnectionManager';
end;

function TMediaConnectionManagerService.GetProtocolInfo:TActionResult;
var
  cmd:TstringList;
  response: TStringStream;
begin
  cmd:=tstringlist.Create;
  response:=TstringStream.Create('');

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:GetProtocolInfo xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">');
  cmd.Add(' </u:GetProtocolInfo>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  if(not SendRequest('urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo',cmd,response))then
    Result:=TActionError.Create(response)
  else
    Result:=TActionResult.Create(response);

  cmd.Free;
  response.Free;
end;

{     TMediaContentDirectoryService     }
constructor TMediaContentDirectoryService.Create(islogged:boolean);
begin
  inherited Create(islogged);
  servicekind:='ContentDirectory';
end;

function TMediaContentDirectoryService.Browse(ObjectID:string;BrowseFlag:string;Filter:string;StartingIndex:string;RequestedCount:string;
      SortCriteria:string;var NumberReturned:UINT64;var TotalMatches:UINT64;var UpdateID:UINT64):TActionResult;
var
  http:TIDHttp;
  cmd:TstringList;
  err:boolean;
  response: TStringStream;
  ares:TActionResult;
begin
  cmd:=tstringlist.Create;
  http:=TIDHttp.Create;
  response:=TstringStream.Create('');

  if Assigned(LogEvent) then
  begin
     http.Intercept:=LogEvent;
     LogEvent.Active:=true;
     LogEvent.Open;
  end;

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">');
  cmd.Add('   <ObjectID>'+ObjectID+'</ObjectID>');
  cmd.Add('   <BrowseFlag>'+BrowseFlag+'</BrowseFlag>');
  cmd.Add('   <Filter>'+Filter+'</Filter>');
  cmd.Add('   <StartingIndex>'+StartingIndex+'</StartingIndex>');
  cmd.Add('   <RequestedCount>'+RequestedCount+'</RequestedCount>');
  cmd.Add('   <SortCriteria>'+SortCriteria+'</SortCriteria>');
  cmd.Add(' </u:Browse>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  try
     http.Request.Clear;
     http.HTTPOptions:=[hoKeepOrigProtocol];
     http.Request.URL:=controlURL;
     http.Request.ContentType := 'text/xml; charset=utf-8';
     http.ProtocolVersion := pv1_1;
     http.Request.UserAgent:='TMediaServer v1.0';
     http.Request.CustomHeaders.Clear;
     http.Request.CustomHeaders.AddValue('SOAPAction','"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"');
     http.Post(baseUrl+controlURL,cmd,response);
  except
     on e:EIdHTTPProtocolException do
     begin
       response.Free;
       response:=TstringStream.Create(E.ErrorMessage);
     end;
     on e:Exception do
     begin
       response:=tstringstream.Create('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '+
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'+
          '<s:Body>'+
          '<s:Fault>'+
          '<faultcode>s:Client</faultcode>'+
          '<faultstring>UPnPError</faultstring>'+
          '<detail>'+
          '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'+
          '<errorCode>General Error</errorCode>'+
          '<errorDescription>'+e.Message+'</errorDescription>'+
          '</UPnPError>'+
          '</detail>'+
          '</s:Fault>'+
          '</s:Body>'+
          '</s:Envelope>');
     end;
  end;

  ares:=TActionError.Create(response);

  if Assigned(LogEvent) then
  begin
     LogEvent.Close;
     LogEvent.Active:=false;
  end;

  Result:=ares;
  cmd.Free;
  http.Free;
  response.Free;
end;


{     TMediaAVService     }
constructor TMediaAVService.Create(islogged:boolean);
begin
  inherited Create(islogged);
  servicekind:='AVTransport';
end;

{
  SetAVTransportURI - set url to play by service
}
function TMediaAVService.SetAVTransportURI(url:string):TActionResult;
var
  cmd:TstringList;
  response: TStringStream;
begin
  cmd:=tstringlist.Create;
  response:=TstringStream.Create('');

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">');
  cmd.Add('   <InstanceID>0</InstanceID>');
  cmd.Add('   <CurrentURI>'+url+'</CurrentURI>');
  cmd.Add('   <CurrentURIMetaData />');
  cmd.Add(' </u:SetAVTransportURI>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  if(not SendRequest('urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI',cmd,response))then
    Result:=TActionError.Create(response)
  else
    Result:=TActionResult.Create(response);

  cmd.Free;
  response.Free;
end;

{
  Stop - stop playing
}
function TMediaAVService.Stop:TActionResult;
var
  cmd:TstringList;
  response: TStringStream;
begin
  cmd:=tstringlist.Create;
  response:=TstringStream.Create('');

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">');
  cmd.Add('   <InstanceID>0</InstanceID>');
  cmd.Add(' </u:Stop>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  if(not SendRequest('urn:schemas-upnp-org:service:AVTransport:1#Stop',cmd,response))then
    Result:=TActionError.Create(response)
  else
    Result:=TActionResult.Create(response);

  cmd.Free;
  response.Free;
end;

{
  GetMediaInfo - returns information associated with the current media
}
function TMediaAVService.GetMediaInfo:TActionResult;
var
  cmd:TstringList;
  response: TStringStream;
begin
  cmd:=tstringlist.Create;
  response:=TstringStream.Create('');

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:GetMediaInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">');
  cmd.Add('   <InstanceID>0</InstanceID>');
  cmd.Add(' </u:GetMediaInfo>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  if(not SendRequest('urn:schemas-upnp-org:service:AVTransport:1#GetMediaInfo',cmd,response))then
    Result:=TActionError.Create(response)
  else
    Result:=TActionResult.Create(response);

  cmd.Free;
  response.Free;
end;

{
  Play - play url, that was set by SetAVTransportURI
}
function TMediaAVService.Play:TActionResult;
var
  cmd:TstringList;
  response: TStringStream;
begin
  cmd:=tstringlist.Create;
  response:=TstringStream.Create('');

  cmd.LineBreak:=#13;
  cmd.Text:='<?xml version="1.0" encoding="utf-8"?>';
  cmd.Add('<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">');
  cmd.Add(' <s:Body>');
  cmd.Add(' <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">');
  cmd.Add('   <InstanceID>0</InstanceID>');
  cmd.Add('   <Speed>1</Speed>');
  cmd.Add(' </u:Play>');
  cmd.Add(' </s:Body>');
  cmd.Add('</s:Envelope>');

  if(not SendRequest('urn:schemas-upnp-org:service:AVTransport:1#Play',cmd,response))then
    Result:=TActionError.Create(response)
  else
    Result:=TActionResult.Create(response);

  cmd.Free;
  response.Free;
end;

function DownloadFile(url:string;saveto:string):boolean;
var
  http:TIDHttp;
  Stream:TMemoryStream;
begin
  Result:=true;
  try
    Stream:=TMemoryStream.Create;
    http:=TIDHttp.Create;
    http.ConnectTimeout:=3000;
    http.ReadTimeout:=4000;
    http.Get(url,Stream);
    Stream.SaveToFile(saveto);
    Stream.Free;
    http.Free;
  except
    on e:EIdConnectTimeout do
    begin
      Result:=false;
      http.Free;
      Stream.Free;
    end;
    on e:Exception do
    begin
      Result:=false;
      http.Free;
      Stream.Free;
    end;
  end;
end;


{     TMediaServer     }
constructor TMediaServer.Create(cIP: String; cPORT:string; cLocation:string; cHomePath:string);
var uri:TIdURI;
begin
    LogService:=false;
    Logo:='';
    LogoType:='';
    IP:=cIP;
    PORT:=cPORT;
    Location:=cLocation;
    HomePath:=cHomePath;
    uri:=TIduri.Create(cLocation);
    BaseLocation:=uri.Protocol+'://'+uri.Host+':'+uri.Port;
    uri.Free;
end;

function TMediaServer.GetServiceCount:integer;
begin
   Result:=0;
   if assigned(ServiceList) then
      Result:=ServiceList.Count;
end;

function TMediaServer.FindService(st:string):TMediaService;
var i:integer;
begin
  Result:=nil;
  if Assigned(ServiceList) then
  for i := 0 to ServiceList.Count - 1 do
      if TMediaService(ServiceList.Items[i]).servicekind=st then
      Result:=ServiceList.Items[i];
end;

procedure TMediaServer.LoadDescription;
var
  XMLDoc: IXMLDocument;
  Node:IXMLNode;
  i,size:integer;
  tmp:TMediaService;
begin
  if(Length(Location)>4)then
  begin

       DeleteFile(TPath.Combine(HomePath, 'descrtmp.xml'));
       if not DownloadFile(Location,TPath.Combine(HomePath, 'descrtmp.xml')) then
       begin
          raise Exception.Create('Cant load server description');
       end;

       XMLDoc:=TXMLDocument.Create(nil);
       XMLDoc.LoadFromFile(TPath.Combine(HomePath, 'descrtmp.xml'));
       if Assigned(XMLDoc) then
       if XMLDoc.DocumentElement<>nil then
       begin

         Node:= XMLDoc.DocumentElement.ChildNodes['device'];
         Modelname:=Node.ChildNodes['modelName'].Text;
         DeviceType:=Node.ChildNodes['deviceType'].Text;
         Manufacturer:=Node.ChildNodes['manufacturer'].Text;
         FriendlyName:=Node.ChildNodes['friendlyName'].Text;
         ModelDescription:=Node.ChildNodes['modelDescription'].Text;


         Node:=Node.ChildNodes['iconList'];

         size:=500;
         for i := 0 to Node.ChildNodes.Count-1 do
         begin
           if(Node.ChildNodes[i].ChildNodes['mimetype'].text='image/png')then
           begin
              if(size>strtoint(Node.ChildNodes[i].ChildNodes['width'].text))then
              begin
                 size:=strtoint(Node.ChildNodes[i].ChildNodes['width'].text);
                 LogoType:='image/png';
                 Logo:=Node.ChildNodes[i].ChildNodes['url'].text;
              end;
           end;
         end;

         if Logo='' then
         begin
           size:=500;
           for i := 0 to Node.ChildNodes.Count-1 do
           begin
             if(Node.ChildNodes[i].ChildNodes['mimetype'].text='image/jpeg')then
             begin
               if(size>strtoint(Node.ChildNodes[i].ChildNodes['width'].text))then
               begin
                 size:=strtoint(Node.ChildNodes[i].ChildNodes['width'].text);
                 LogoType:='image/jpeg';
                 Logo:=Node.ChildNodes[i].ChildNodes['url'].text;
               end;
             end;
           end;
         end;


         if Logo>'-' then
         begin
            if Logo[Low(Logo)]<>'/' then Logo:='/'+Logo;

            if LogoType='image/png' then
            begin
              DownLoadFile(BaseLocation+Logo,TPath.Combine(HomePath, Modelname+'.png'));
            end;
         end;

         //getting services list
         Node:= XMLDoc.DocumentElement.ChildNodes['device'].ChildNodes['serviceList'];
         if Node.HasChildNodes then
            ServiceList:=TObjectList<TMediaService>.Create(true);

         for i := 0 to Node.ChildNodes.Count-1 do
         begin
           //creating services
           if Node.ChildNodes[i].ChildNodes['serviceType'].Text.Substring(0,41)='urn:schemas-upnp-org:service:AVTransport:' then
             tmp:=TMediaAVService.Create(LogService)
           else
           if Node.ChildNodes[i].ChildNodes['serviceType'].Text.Substring(0,46)='urn:schemas-upnp-org:service:ContentDirectory:' then
             tmp:=TMediaContentDirectoryService.Create(LogService)
           else
           if Node.ChildNodes[i].ChildNodes['serviceType'].Text.Substring(0,47)='urn:schemas-upnp-org:service:ConnectionManager:' then
             tmp:=TMediaConnectionManagerService.Create(LogService)
           else
             tmp:=TMediaService.Create(LogService);

           tmp.serviceType:=Node.ChildNodes[i].ChildNodes['serviceType'].Text;
           tmp.serviceId:=Node.ChildNodes[i].ChildNodes['serviceId'].Text;
           tmp.SCPDURL:=Node.ChildNodes[i].ChildNodes['SCPDURL'].Text;
           tmp.controlURL:=Node.ChildNodes[i].ChildNodes['controlURL'].Text;
           tmp.baseURL:=Self.BaseLocation;
           tmp.eventSubURL:=Node.ChildNodes[i].ChildNodes['eventSubURL'].Text;

           if tmp.controlURL>'-' then
            if tmp.controlURL[Low(tmp.controlURL)]<>'/' then tmp.controlURL:='/'+tmp.controlURL;


           ServiceList.Add(tmp);
         end;

       end;
  end;

end;

destructor TMediaServer.Destroy;
begin
   if Assigned(ServiceList) then
   begin
     ServiceList.Clear;
     ServiceList.Free;
   end;
   inherited;
end;



end.
