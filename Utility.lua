local UtilityInternal = {};
UtilityInternal.DebugLogging = false;

Utility = UtilityInternal;

luanet.load_assembly("System");

local types = {};
types["System.Type"] = luanet.import_type("System.Type");

local function Log(input, debugOnly)
  debugOnly = debugOnly or false;

  if ((not debugOnly) or (debugOnly and UtilityInternal.DebugLogging)) then
    local t = type(input);

    if (t == "string" or t == "number") then
      LogDebug(input);
    elseif (t == "table") then
      LogTable(input);
    elseif (t == "nil") then
      LogDebug("(nil)");
    elseif (t == "boolean") then
      if (input == true) then
        LogDebug("True");
      else
        LogDebug("False");
      end
    elseif (t == "function") then
      local success, result = pcall(input);

      if (success) then
        Log(result, debugOnly);
      end
    elseif (t == "userdata") then
      if (IsType(input, "System.Exception")) then
        LogException(input);
      else
        pcall(function()
        LogDebug(input:ToString());
        end);
      end
    end
  end
end

local function Trim(s)
  if s == nil then return "" end
  local n = s:find"%S"
  return n and s:match(".*%S", n) or ""
end

local function IsType(o, t, checkFullName)
  if ((o and type(o) == "userdata") and (t and type(t) == "string")) then
    local comparisonType = types["System.Type"].GetType(t);
    if (comparisonType) then
      return comparisonType:IsAssignableFrom(o:GetType()), true;
    else
      if(checkFullName) then
        return (o:GetType().FullName == t), false;
      else
        return (o:GetType().Name == t), false;
      end
    end
  end
  return false, false;
end

local function LogIndented(entry, depth)
  depth = (depth or 0);
  LogDebug(string.rep("> ", depth) .. entry);
end

local function LogTable(input, depth)
  if(input == nil) then return end
  depth = (depth or 0);

  for key, value in pairs(input) do
    if (value and type(value) == "table") then
      LogIndented("Key: " .. key, depth);
      LogTable(value, depth + 1);
    else
      local success, result = pcall(string.format, "%s", (value or "(nil)"));
      if (success) then
        LogIndented("Key: " .. key .. " = " .. (value or "(nil)"), depth);
      else
        LogIndented("Key: " .. key .. " = (?)", depth);
      end
    end
  end
end

function LogException(exception, depth)
  depth = (depth or 0);
  if (exception) then
    LogIndented(exception.Message, depth);
    if(exception.InnerException) then
        LogException(exception.InnerException, depth + 1);
    end
  end
end

function URLDecode(s)
  s = string.gsub(s, "+", " ");
  s = string.gsub(s, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16));
  end);
  s = string.gsub(s, "\r\n", "\n");
  return s;
end

function StringSplit(delimiter, text)
  if delimiter == nil then
    delimiter = "%s"
  end
  if text == nil then return {} end
  
  local t={};
  local i=1;
  for str in string.gmatch(text, "([^"..delimiter.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

local function URLEncode(s)
  if (s) then
    s = string.gsub(s, "\n", "\r\n")
    s = string.gsub(s, "([^%w %-%_%.%~])",
    function (c)
      return string.format("%%%02X", string.byte(c))
    end);
    s = string.gsub(s, " ", "+")
  end
  return s
end

UtilityInternal.Trim = Trim;
UtilityInternal.IsType = IsType;
UtilityInternal.Log = Log;
UtilityInternal.URLDecode = URLDecode;
UtilityInternal.URLEncode = URLEncode;
UtilityInternal.StringSplit = StringSplit;