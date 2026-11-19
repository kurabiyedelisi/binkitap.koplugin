-- Kullanım: texlua test/sozdizimi.lua binkitap.koplugin/*.lua
local hata = false
for _, f in ipairs(arg) do
  local fn, err = loadfile(f)
  print(fn and ("OK   " .. f) or ("HATA " .. err))
  if not fn then hata = true end
end
os.exit(hata and 1 or 0)
