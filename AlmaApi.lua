local AlmaApiInternal = {};
AlmaApiInternal.ApiUrl = nil;
AlmaApiInternal.ApiKey = nil;

local types = {};
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
types["System.Xml.XmlTextReader"] = luanet.import_type("System.Xml.XmlTextReader");
types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");

-- Create a logger
local log = types["log4net.LogManager"].GetLogger(rootLogger .. ".AlmaApi");

AlmaApi = AlmaApiInternal;

-- EXISTING: Retrieve Item (used to get IDs)
local function RetrieveItemByBarcode( barcode )
    local requestUrl = AlmaApiInternal.ApiUrl .. "items?apikey="..
         Utility.URLEncode(AlmaApiInternal.ApiKey) .. "&item_barcode=" .. Utility.URLEncode(barcode);
    local headers = {"Accept: application/xml", "Content-Type: application/xml"};
    log:DebugFormat("Request URL: {0}", requestUrl);

    local response = WebClient.GetRequest(requestUrl, headers);
    log:DebugFormat("response = {0}", response);

    return WebClient.ReadResponse(response);
end

-- NEW: Helper to parse IDs needed for the request
local function ParseItemIds(itemXmlRecord)
    if itemXmlRecord == nil then return nil, nil, nil end
    
    local mmsId = nil
    local holdingId = nil
    local itemPid = nil
    
    local mmsNode = itemXmlRecord:SelectSingleNode("//bib_data/mms_id")
    local holdNode = itemXmlRecord:SelectSingleNode("//holding_data/holding_id")
    local pidNode = itemXmlRecord:SelectSingleNode("//item_data/pid")

    if mmsNode then mmsId = mmsNode.InnerText end
    if holdNode then holdingId = holdNode.InnerText end
    if pidNode then itemPid = pidNode.InnerText end

    return mmsId, holdingId, itemPid
end

-- NEW: Place Request on Item
local function PlaceRequest(mmsId, holdingId, itemPid, requesterUserId, pickupLibrary)
    -- Endpoint: /bibs/{mms_id}/holdings/{holding_id}/items/{item_pid}/requests
    local requestUrl = AlmaApiInternal.ApiUrl .. "bibs/" .. mmsId .. 
                       "/holdings/" .. holdingId .. 
                       "/items/" .. itemPid .. 
                       "/requests"
    
    -- Query Params
    requestUrl = requestUrl .. "?user_id=" .. Utility.URLEncode(requesterUserId) .. 
                 "&user_id_type=all_unique" ..
                 "&apikey=" .. Utility.URLEncode(AlmaApiInternal.ApiKey)

    -- XML Body
    local xmlBody = [[
        <user_request>
            <request_type>HOLD</request_type>
            <pickup_location_type>LIBRARY</pickup_location_type>
            <pickup_location_library>]] .. pickupLibrary .. [[</pickup_location_library>
            <comment>ILLiad Routing Request</comment>
        </user_request>
    ]]

    local headers = {
        "Content-Type: application/xml",
        "Accept: application/xml"
    }

    log:Debug("Sending PlaceRequest to Alma...")
    log:Debug("URL: " .. requestUrl)
    
    local responseString = WebClient.PostRequest(requestUrl, headers, xmlBody)
    
    return WebClient.ReadResponse(responseString)
end

-- Exports
AlmaApi.RetrieveItemByBarcode = RetrieveItemByBarcode;
AlmaApi.ParseItemIds = ParseItemIds;
AlmaApi.PlaceRequest = PlaceRequest;