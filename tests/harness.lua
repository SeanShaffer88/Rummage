-- Shared Lua 5.1 mock-suite runner; used by lupa and the native interpreter.
return function(files, sources, cases_src, report)
  local passed, failed = 0, 0
  local T = {}
  local function new_env()
    local env = WOWSTUB()
    setmetatable(env, { __index = function(t, k)
      local v = _G[k]
      if v ~= nil then return v end
      local ok = false
      if type(k) == "string" then
        for _, pre in ipairs({"Get","Set","Is","Has","Clear","Click","Use","Pick","Show","Hide","Open","Close","Toggle","Register","Unregister","Play","Stop","Start","Cancel","Accept","Equip","Buy","Sell","Can","Do","Reset","Update","Request","Run","Pickup","Put","Cursor","Auto","Unit","Set"}) do
          if k:sub(1, #pre) == pre and k:sub(#pre + 1, #pre + 1):match("%u") then ok = true break end
        end
      end
      if ok then
        env.__auto = env.__auto or {}
        env.__auto[k] = true
        return function() end
      end
    end })
    env._G = env
    local ns = {}
    for _, f in ipairs(files) do
      local chunk, err = loadstring(sources[f], "@" .. f)
      if not chunk then error("compile " .. f .. ": " .. tostring(err)) end
      setfenv(chunk, env)
      chunk("Rummage", ns)
    end
    return env, ns
  end
  local env_mt = {}
  local cases, loadErr = loadstring(cases_src, "@cases.lua")
  if not cases then error(loadErr) end
  local ctx = { new_env = new_env, tests = {} }
  setfenv(cases, setmetatable({ T = ctx, WOWSTUB = WOWSTUB }, { __index = _G }))
  cases()
  for _, t in ipairs(ctx.tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1; report(true, t.name, "")
    else failed = failed + 1; report(false, t.name, tostring(err)) end
  end
  return passed, failed
end
