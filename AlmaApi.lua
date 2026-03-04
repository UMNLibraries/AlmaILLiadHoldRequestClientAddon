local AlmaApiInternal = {};
AlmaApiInternal.ApiUrl = nil;
AlmaApiInternal.ApiKey = nil;

local types = {};
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.Xml.XmlTextReader"] = luanet.import_type("System.Xml.XmlTextReader");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");

local log = types["log4net.LogManager"].GetLogger(rootLogger .. ".AlmaApi");

AlmaApi = AlmaApiInternal;

local function GetBaseUrl(mmsId, holdingId, itemPid)
    return AlmaApiInternal.ApiUrl .. "bibs/" .. mmsId .. 
           "/holdings/" .. holdingId .. 
           "/items/" .. itemPid
end

local function RetrieveItemByBarcode(barcode)
    local requestUrl = AlmaApiInternal.ApiUrl .. "items?apikey="..
         Utility.URLEncode(AlmaApiInternal.ApiKey) .. "&item_barcode=" .. Utility.URLEncode(barcode);
    
    local headers = {"Accept: application/xml", "Content-Type: application/xml"};
    log:Debug("Request URL: " .. requestUrl);

    local response = WebClient.GetRequest(requestUrl, headers);
    return WebClient.ReadResponse(response);
end

local function ParseItemIds(itemXml)
    if itemXml == nil then return nil, nil, nil end
    
    local mmsId = nil;
    local holdingId = nil;
    local itemPid = nil;

    local bibData = itemXml:SelectSingleNode("//bib_data");
    local holdingData = itemXml:SelectSingleNode("//holding_data");
    local itemData = itemXml:SelectSingleNode("//item_data");

    if bibData then mmsId = bibData:SelectSingleNode("mms_id").InnerText end
    if holdingData then holdingId = holdingData:SelectSingleNode("holding_id").InnerText end
    if itemData then itemPid = itemData:SelectSingleNode("pid").InnerText end

    return mmsId, holdingId, itemPid;
end

-- Updated PlaceRequest to handle allowSameRequest
local function PlaceRequest(mmsId, holdingId, itemPid, requesterUserId, pickupLibrary, transactionNumber, allowSameRequest)
    local requestUrl = GetBaseUrl(mmsId, holdingId, itemPid) .. "/requests" ..
                 "?user_id=" .. Utility.URLEncode(requesterUserId) .. 
                 "&user_id_type=all_unique" ..
                 "&apikey=" .. Utility.URLEncode(AlmaApiInternal.ApiKey)

    if allowSameRequest then
         requestUrl = requestUrl .. "&allow_same_request=true"
    end

    local commentText = "ILLiad Lending Request " .. (transactionNumber or "")

    local xmlBody = [[
        <user_request>
            <request_type>HOLD</request_type>
            <pickup_location_type>LIBRARY</pickup_location_type>
            <pickup_location_library>]] .. pickupLibrary .. [[</pickup_location_library>
            <comment>]] .. commentText .. [[</comment>
        </user_request>
    ]]

    local headers = {"Content-Type: application/xml", "Accept: application/xml"}
    local responseString = WebClient.PostRequest(requestUrl, headers, xmlBody)
    
    return WebClient.ReadResponse(responseString)
end

local function GetRequest(mmsId, holdingId, itemPid, requestId)
    local requestUrl = GetBaseUrl(mmsId, holdingId, itemPid) .. "/requests/" .. requestId ..
                       "?apikey=" .. Utility.URLEncode(AlmaApiInternal.ApiKey);

    local headers = {"Accept: application/xml"};
    local response = WebClient.GetRequest(requestUrl, headers);
    
    return WebClient.ReadResponse(response);
end

-- Updated CancelRequest to pass reason and note
local function CancelRequest(mmsId, holdingId, itemPid, requestId, reason, note)
    local requestUrl = GetBaseUrl(mmsId, holdingId, itemPid) .. "/requests/" .. requestId ..
                       "?reason=" .. Utility.URLEncode(reason) ..
                       "&note=" .. Utility.URLEncode(note) ..
                       "&apikey=" .. Utility.URLEncode(AlmaApiInternal.ApiKey);

    log:Debug("Attempting DELETE on URL: " .. requestUrl);

    local client = types["System.Net.WebClient"]();
    client.Encoding = types["System.Text.Encoding"].UTF8;
    client.Headers:Add("Accept", "application/xml");
    
    local success, result = pcall(function() 
        return client:UploadString(requestUrl, "DELETE", "");
    end);

    if success then
        log:Info("Cancel successful.");
        return true;
    else
        log:Error("Cancel Failed: " .. tostring(result));
        return false;
    end
end

AlmaApi.RetrieveItemByBarcode = RetrieveItemByBarcode;
AlmaApi.ParseItemIds = ParseItemIds;
AlmaApi.PlaceRequest = PlaceRequest;
AlmaApi.GetRequest = GetRequest;
AlmaApi.CancelRequest = CancelRequest;