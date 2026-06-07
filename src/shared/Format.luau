--!strict
--[[
	Format
	------
	Petites fonctions de formatage des nombres (argent, watts).
	Partagé serveur/client (ReplicatedStorage.Shared).
	Ex : 1500 -> "1.5K", 2_300_000 -> "2.3M"
]]

local Format = {}

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- Format compact : 1 250 -> "1.25K"
function Format.Short(n: number): string
	n = tonumber(n) or 0
	local negative = n < 0
	n = math.abs(n)

	local idx = 1
	while n >= 1000 and idx < #SUFFIX do
		n /= 1000
		idx += 1
	end

	local s: string
	if idx == 1 then
		-- Pas de suffixe : on affiche un entier
		s = string.format("%d", math.floor(n + 0.5))
	else
		-- Avec suffixe : 2 décimales, puis on retire les zéros inutiles
		s = string.format("%.2f", n)
		s = (s:gsub("%.?0+$", "")) -- "12.30" -> "12.3", "12.00" -> "12"
		s ..= SUFFIX[idx]
	end

	if negative then
		s = "-" .. s
	end
	return s
end

-- Argent : "$1.5K"
function Format.Money(n: number): string
	return "$" .. Format.Short(n)
end

-- Watts : "1.5K W"
function Format.Watts(n: number): string
	return Format.Short(n) .. " W"
end

-- Nombre entier avec séparateurs de milliers : 1234567 -> "1 234 567"
function Format.Comma(n: number): string
	local s = string.format("%d", math.floor(tonumber(n) or 0))
	local formatted = s
	while true do
		local replaced: number
		formatted, replaced = formatted:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

return Format
