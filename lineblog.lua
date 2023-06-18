dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")
local https = require("ssl.https")
JSON = (loadfile "JSON.lua")()

local item_dir = os.getenv("item_dir")
local warc_file_base = os.getenv("warc_file_base")
local concurrency = tonumber(os.getenv("concurrency"))
local item_type = nil
local item_name = nil
local item_value = nil
local item_user = nil

if urlparse == nil or http == nil then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false
local killgrab = false
local logged_response = false

local discovered_outlinks = {}
local discovered_items = {}
local bad_items = {}
local ids = {}

local retry_url = false
local allow_video = false

local postpagebeta = false
local webpage_404 = false

math.randomseed(os.time())

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

abort_item = function(item)
  abortgrab = true
  if not item then
    item = item_name
  end
  if not bad_items[item] then
    io.stdout:write("Aborting item " .. item .. ".\n")
    io.stdout:flush()
    bad_items[item] = true
  end
end

kill_grab = function(item)
  io.stdout:write("Aborting crawling.\n")
  killgrab = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

processed = function(url)
  if downloaded[url] or addedtolist[url] then
    return true
  end
  return false
end

discover_item = function(target, item)
  if not target[item] then
    if string.match(item, "boxsmall") then
      discover_item(target, string.gsub(item, "boxsmall", "boxlarge"))
    end
print('discovered', item)
    target[item] = true
    return true
  end
  return false
end

find_item = function(url)
  local value = string.match(url, "^https?://[^/]*lineblog%.me/([a-zA-Z0-9%-_]+)/$")
  local type_ = "blog"
  if not value then
    value = string.match(url, "^https?://obs%.line%-scdn%.net/([a-zA-Z0-9%-_]+)$")
    type_ = "cdn-obs"
  end
  if not value then
    value = string.match(url, "^https?://[^/]*lineblog%.me/tag/([a-zA-Z0-9%%%-_]+)$")
    type_ = "tag"
  end
  if not value then
    value = string.match(url, "^https?://blog%-api%.line%-apps%.com/v1/search/articles%?keyword=([a-zA-Z0-9%%%-_]+)$")
    type_ = "keyword"
  end
  if not value then
    value = string.match(url, "^https?://resize%-image%.lineblog%.me/(.+)$")
    type_ = "resize"
  end
  if not value then
    other, value = string.match(url, "^https?://blog%-api%.line%-apps%.com/v1/blog/([^/]+)/article/([0-9]+)/info$")
    type_ = "post"
  end
  if value then
    return {
      ["value"]=value,
      ["type"]=type_,
      ["other"]=other
    }
  end
end

set_item = function(url)
  found = find_item(url)
  if found then
    item_type = found["type"]
    item_value = found["value"]
    if item_type == "post" then
      item_user = found["other"]
      item_name_new = item_type .. ":" .. item_user .. ":" .. item_value
    else
      item_name_new = item_type .. ":" .. item_value
    end
    if item_name_new ~= item_name then
      ids = {}
      ids[item_value] = true
      abortgrab = false
      initial_allowed = false
      tries = 0
      retry_url = false
      allow_video = false
      webpage_404 = false
      item_name = item_name_new
      print("Archiving item " .. item_name)
    end
  end
end

allowed = function(url, parenturl)
  if ids[url] then
    return true
  end

  if string.match(url, "/<")
    or string.match(url, "/'%+urls")
    or string.match(url, "/index%.rdf$")
    or not string.match(url, "^https?://") then
    return false
  end

  for pattern, type_ in pairs({
    ["^https?://obs%.line%-scdn%.net/([a-zA-Z0-9%-_]+)"]="cdn-obs",
    ["^https?://[^/]*lineblog%.me/([a-zA-Z0-9%-_]+)/"]="blog",
    ["^https?://[^/]*lineblog%.me/tag/([a-zA-Z0-9%%%-_]+)"]="tag",
    ["^https?://resize%-image%.lineblog%.me/(.+)$"]="resize",
    ["https?://[^/]*lineblog%.me/([^/]+)/archives/([0-9]+)%.html"]="post",
    ["^https?://blog%.line%-apps%.com/v1/blog/([^/]+)/article/([0-9]+)"]="post"
  }) do
    local match = nil
    if type_ == "post" then
      match, other = string.match(url, pattern)
    else
      match = string.match(url, pattern)
    end
    if match then
      if type_ == "post" then
        match = match .. ":" .. other
      end
      local new_item = type_ .. ":" .. match
      if new_item ~= item_name then
        discover_item(discovered_items, new_item)
        return false
      end
    end
  end

  if string.match(url, "^https?://[^/]*line[^/]*/") then
    for _, pattern in pairs({
      "([a-zA-Z0-9%-_]+)",
      "([a-zA-Z0-9%%%-_]+)",
      "([^/%?&]]+)"
    }) do
      for s in string.gmatch(string.match(url, "^https?://[^/]+(/.*)"), pattern) do
        if ids[s] then
          return true
        end
      end
    end
  end

  if not string.match(url, "^https?://[^/]*lineblog%.me/")
    and not string.match(url, "^https?://[^/]*line%-scdn%.net/")
    and not string.match(url, "^https?://blog%.line%-apps%.com/")
    and not string.match(url, "^https?://www%.facebook%.com/share%.php%?")
    and not string.match(url, "^https?://www%.facebook%.com/sharer%.php%?")
    and not string.match(url, "^https?://www%.facebook%.com/sharer/sharer%.php%?")
    and not string.match(url, "^https?://twitter%.com/intent/tweet%?")
    and not string.match(url, "^https?://twitter%.com/share%?") then
    discover_item(discovered_outlinks, url)
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if allowed(url, parent["url"]) and not processed(url) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  if abortgrab then
    return {}
  end

  local function decode_codepoint(newurl)
    newurl = string.gsub(
      newurl, "\\[uU]([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])",
      function (s)
        return unicode_codepoint_as_utf8(tonumber(s, 16))
      end
    )
    return newurl
  end

  local function fix_case(newurl)
    if not string.match(newurl, "^https?://.") then
      return newurl
    end
    if string.match(newurl, "^https?://[^/]+$") then
      newurl = newurl .. "/"
    end
    local a, b = string.match(newurl, "^(https?://[^/]+/)(.*)$")
    return string.lower(a) .. b
  end

  local function check(newurl)
    newurl = decode_codepoint(newurl)
    newurl = fix_case(newurl)
    local origurl = url
    if string.len(url) == 0 then
      return nil
    end
    local url = string.match(newurl, "^([^#]+)")
    local url_ = string.match(url, "^(.-)[%.\\]*$")
    while string.find(url_, "&amp;") do
      url_ = string.gsub(url_, "&amp;", "&")
    end
    if not processed(url_)
      and not processed(url_ .. "/")
      and allowed(url_, origurl) then
print('QUEUING', url_)
      if string.match(url_, "^https?://blog%-api%.line%-apps%.com/v1/") then
        table.insert(urls, {
          url=url_,
          headers={
            ["User-Agent"]="okhttp/4.7.2"
          }
        })
      elseif string.match(url_, "^https?://[^/]*lineblog%.me/api/tag/") then
        table.insert(urls, {
          url=url_,
          headers={
            ["Accept"] = "application/json, text/javascript, */*; q=0.01",
            ["X-Requested-With"] = "XMLHttpRequest"
          }
        })
      elseif string.match(url_, "^https?://blog%.line%-apps%.com/v1/blog/") then
        table.insert(urls, {
          url=url_,
          headers={
            ["User-Agent"] = "LineBlog/1.7.8 (Linux; U; Android 13; Pixel 6a Build/SD2A.220601.001.B1)",
            ["Accept-Language"] = "ja"
          }
        })
      else
        table.insert(urls, { url=url_ })
      end
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    newurl = decode_codepoint(newurl)
    if string.match(newurl, "['\"><]") then
      return nil
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    newurl = decode_codepoint(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (
      string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^data:")
      or string.match(newurl, "^irc:")
      or string.match(newurl, "^%${")
    ) then
      check(urlparse.absolute(url, newurl))
    end
  end

  if item_type == "cdn-obs"
    and not string.match(url, "^https://[^/]+/[^/]+/[a-z]+$") then
    check(url .. "/small")
    check(url .. "/large")
  end

  local inner_url = string.match(url, "..-(https?://.+)$")
  if inner_url then
    check(inner_url)
  end

  if item_type == "blog" then
    local base_api_url = "https://blog-api.line-apps.com/v1/blog/" .. item_value
    for _, i in pairs({"0", "1"}) do
      local base_url = base_api_url .. "/articles?withBlog=" .. i
      check(base_url)
      check(base_url .. "&pageKey=1")
    end
    check(base_api_url .. "/articles")
    check(base_api_url .. "/articles?pageKey=1")
    check(base_api_url .. "/followers/list")
    check(base_api_url .. "/followers/list?pageKey=1")
    check(base_api_url .. "/follow/list")
    check(base_api_url .. "/follow/list?pageKey=1")
  end

  if item_type == "tag" then
    local base_api_url = "https://blog-api.line-apps.com/v1/explore/tag?tag=" .. item_value
    check(base_api_url)
    for _, i in pairs({"0", "1"}) do
      local base_url = base_api_url .. "&withTag=" .. i
      check(base_url)
      check(base_url .. "&pageKey=1")
    end
    base_api_url = "https://www.lineblog.me/api/tag/?tag=" .. item_value .. "&blogName="
    check(base_api_url)
    check(base_api_url .. "&pageKey=1")
  end

  if item_type == "keyword" then
    local base_url = "https://blog-api.line-apps.com/v1"
    check(base_url .. "/search/articles?keyword=" .. item_value)
    check(base_url .. "/search/articles?keyword=" .. item_value .. "&pageKey=1")
    check(base_url .. "/search/tags?keyword=" .. item_value)
    check(base_url .. "/search/tags?keyword=" .. item_value .. "&pageKey=1")
    check(base_url .. "/search/users?keyword=" .. item_value)
    check(base_url .. "/search/users?keyword=" .. item_value .. "&pageKey=1")
    check(base_url .. "/suggest/tags?keyword=" .. item_value)
    check(base_url .. "/suggest/tags?keyword=" .. item_value .. "&pageKey=1")
  end

  if item_type == "post" then
    if string.match(url, "^https?://[^/]*lineblog%.me/([^/]+)/archives/([0-9]+)%.html") then
      check("https://blog-api.line-apps.com/v1/blog/article/info?url=" .. url)
    end
    local base_url = "https://blog-api.line-apps.com/v1/blog/" .. item_user .. "/article/" .. item_value
    check(base_url .. "/info")
    check(base_url .. "/comment/list")
    check(base_url .. "/comment/list?pageKey=1")
    check(base_url .. "/reblog/list")
    check(base_url .. "/reblog/list?pageKey=1")
    check(base_url .. "/like/list")
    check(base_url .. "/like/list?pageKey=1")
  end

  if allowed(url)
    and status_code < 300
    and item_type ~= "cdn-obs"
    and item_type ~= "resize" then
    html = read_file(file)
    local is_blog_api = string.match(url, "^https?://blog%-api%.line%-apps%.com/v1/")
    local is_tag_api = string.match(url, "^https?://[^/]*lineblog%.me/api/tag/")
    if is_blog_api or is_tag_api then
      local json = JSON:decode(html)
      local next_page_key = nil
      if is_blog_api then
        assert(json["status"] == 200)
        json = json["data"]
      elseif is_tag_api then
        assert(json["status"] == "success")
      else
        error()
      end
      local next_page_key = json["nextPageKey"]
      if next_page_key then
        next_page_key = tostring(next_page_key)
        local newurl = url
        if not string.match(url, "[%?&]pageKey=") then
          if string.match(url, "%?") then
            newurl = newurl .. "&"
          else
            newurl = newurl .. "?"
          end
          newurl = newurl .. "pageKey=" .. next_page_key
        else
          newurl = string.gsub(newurl, "([%?&]pageKey=)[0-9]+", "%1" .. next_page_key)
        end
        check(newurl)
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
    html = string.gsub(html, "&gt;", ">")
    html = string.gsub(html, "&lt;", "<")
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.write_to_warc = function(url, http_stat)
  status_code = http_stat["statcode"]
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. " \n")
  io.stdout:flush()
  logged_response = true
  set_item(url["url"])
  if not item_name then
    error("No item name found.")
  end
  if string.match(url["url"], "^https?://blog%-api%.line%-apps%.com/v1/")
    or string.match(url["url"], "^https?://[^/]*lineblog%.me/api/tag/") then
    local html = read_file(http_stat["local_file"])
    local status = JSON:decode(html)["status"]
    if status == 500
      and (
        string.match(url["url"], "/search/")
        or string.match(url["url"], "/suggest/")
      )
      and (
        string.match(url["url"], "[%?&]pageKey=501")
        or string.match(url["url"], "[%?&]pageKey=1001")
      ) then
      print("Reached the end of search!")
      return false
    elseif status ~= 200 and status ~= "success" then
      print("Bad API response.")
      retry_url = true
      return false
    end
  end
  if http_stat["statcode"] ~= 200
    and http_stat["statcode"] ~= 301 then
    retry_url = true
    return false
  end
  if abortgrab then
    print("Not writing to WARC.")
    return false
  end
  retry_url = false
  tries = 0
  return true
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  if not logged_response then
    url_count = url_count + 1
    io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. " \n")
    io.stdout:flush()
  end
  logged_response = false

  if killgrab then
    return wget.actions.ABORT
  end

  set_item(url["url"])

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if processed(newloc) or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code < 400 then
    downloaded[url["url"]] = true
  end

  if abortgrab then
    abort_item()
    return wget.actions.EXIT
  end

  if status_code == 0 or retry_url then
    io.stdout:write("Server returned bad response.")
    io.stdout:flush()
    tries = tries + 1
    if tries > 5 then
      io.stdout:write(" Skipping.\n")
      io.stdout:flush()
      tries = 0
      abort_item()
      return wget.actions.EXIT
    end
    local sleep_time = math.random(
      math.floor(math.pow(2, tries-0.5)),
      math.floor(math.pow(2, tries))
    )
    io.stdout:write("Sleeping " .. sleep_time .. " seconds.\n")
    io.stdout:flush()
    os.execute("sleep " .. sleep_time)
    return wget.actions.CONTINUE
  end

  tries = 0

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local function submit_backfeed(items, key)
    local tries = 0
    local maxtries = 10
    while tries < maxtries do
      if killgrab then
        return false
      end
      local body, code, headers, status = http.request(
        "https://legacy-api.arpa.li/backfeed/legacy/" .. key,
        items .. "\0"
      )
      if code == 200 and body ~= nil and JSON:decode(body)["status_code"] == 200 then
        io.stdout:write(string.match(body, "^(.-)%s*$") .. "\n")
        io.stdout:flush()
        return nil
      end
      io.stdout:write("Failed to submit discovered URLs." .. tostring(code) .. tostring(body) .. "\n")
      io.stdout:flush()
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
    end
    kill_grab()
    error()
  end

  local file = io.open(item_dir .. "/" .. warc_file_base .. "_bad-items.txt", "w")
  for url, _ in pairs(bad_items) do
    file:write(url .. "\n")
  end
  file:close()
  for key, data in pairs({
    ["lineblog-2dl321sh5basniqz"] = discovered_items,
    ["urls-g8mpqd0ko0rbabiv"] = discovered_outlinks
  }) do
    print('queuing for', string.match(key, "^(.+)%-"))
    local items = nil
    local count = 0
    for item, _ in pairs(data) do
      print("found item", item)
      if items == nil then
        items = item
      else
        items = items .. "\0" .. item
      end
      count = count + 1
      if count == 100 then
        submit_backfeed(items, key)
        items = nil
        count = 0
      end
    end
    if items ~= nil then
      submit_backfeed(items, key)
    end
  end
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if killgrab then
    return wget.exits.IO_FAIL
  end
  if abortgrab then
    abort_item()
  end
  return exit_status
end


