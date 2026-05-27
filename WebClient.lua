WebClient = {};

local types = {};
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.Xml.XmlTextReader"] = luanet.import_type("System.Xml.XmlTextReader");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");
types["System.IO.StreamReader"] = luanet.import_type("System.IO.StreamReader");

-- Create a logger
local log = types["log4net.LogManager"].GetLogger(rootLogger .. ".WebClient");

-- Helper to safely unpack nested web exception messages and response bodies
local function GetWebExceptionMessage(exception)
    local message = "";
    if exception and exception.Message then
        message = exception.Message;
        if (exception.InnerException) then
            message = message .. "\r\n" .. GetWebExceptionMessage(exception.InnerException);
            if exception.InnerException.Response and exception.InnerException.Response ~= "Response" then
                -- This is necessary to get the response body from exceptions thrown by WebClients.
                local streamReader = types["System.IO.StreamReader"](exception.InnerException.Response:GetResponseStream());
                local responseContent = streamReader:ReadToEnd();
                log:DebugFormat("Web exception response: {0}", Utility.Redact(responseContent));
            end
        end
    elseif exception then
        message = tostring(exception);
    end
    return message;
end

local function GetRequest(requestUrl, headers)
    local webClient = types["System.Net.WebClient"]();
    local response = nil;
    log:Debug("Created Web Client");
    webClient.Encoding = types["System.Text.Encoding"].UTF8;

    for _, header in ipairs(headers) do
        webClient.Headers:Add(header);
    end

    local success, error = pcall(function ()
        response = webClient:DownloadString(requestUrl);
    end);

    webClient:Dispose();
    log:Debug("Disposed Web Client");

    if(success) then
        return response;
    else
        log:InfoFormat("Unable to get response from the request url: {0}", Utility.Redact(GetWebExceptionMessage(error)));
    end
end

-- Handle POST requests
local function PostRequest(requestUrl, headers, body)
    local webClient = types["System.Net.WebClient"]();
    local response = nil;
    log:Debug("Created Web Client for POST");
    webClient.Encoding = types["System.Text.Encoding"].UTF8;

    for _, header in ipairs(headers) do
        webClient.Headers:Add(header);
    end

    local success, error = pcall(function ()
        response = webClient:UploadString(requestUrl, "POST", body);
    end);

    webClient:Dispose();
    log:Debug("Disposed Web Client");

    if(success) then
        return response;
    else
        log:InfoFormat("Unable to post response to the request url: {0}", Utility.Redact(GetWebExceptionMessage(error)));
        return nil;
    end
end

local function ReadResponse( responseString )
    if (responseString and #responseString > 0) then

        local responseDocument = types["System.Xml.XmlDocument"]();

        local documentLoaded, error = pcall(function ()
            responseDocument:LoadXml(responseString);
        end);

        if (documentLoaded) then
            return responseDocument;
        else
            log:InfoFormat("Unable to load response content as XML: {0}", Utility.Redact(tostring(error)));
            return nil;
        end
    else
        log:Info("Response string is nil or empty.");
        return nil;
    end
end

WebClient.GetRequest = GetRequest;
WebClient.PostRequest = PostRequest;
WebClient.ReadResponse = ReadResponse;