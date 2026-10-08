if isServer() then return end
require("improvedhairmenu/Components/VisualAvatar")

HairAvatar = VisualAvatar:derive("HairAvatar")

--[[ Che cosa manca per fare questo taglio, come frase gia' pronta.

	Prima il rifiuto era muto: si cliccava e non succedeva niente, senza un
	motivo. Ora il personaggio dice cosa gli serve.
]]
local function missingTools(req)
	local mancanti = {}

	if req.hairgel == false then
		table.insert(mancanti, getText("UI_IHM_Need_HairGel") or "hair gel")
	end

	local hasScissors = req.scissors
	local hasRazor    = req.razor

	if hasScissors ~= nil and hasRazor ~= nil then
		-- Tutti e due presenti fra i requisiti: ne basta uno.
		if hasScissors == false and hasRazor == false then
			table.insert(mancanti, getText("UI_IHM_Need_ScissorsOrRazor") or "scissors or a razor")
		end
	else
		if hasScissors == false then table.insert(mancanti, getText("UI_IHM_Need_Scissors") or "scissors") end
		if hasRazor == false then table.insert(mancanti, getText("UI_IHM_Need_Razor") or "a razor") end
	end

	if #mancanti == 0 then return nil end
	return table.concat(mancanti, ", ")
end

function HairAvatar:select()
	-- Don't allow selection of hairs missing a requirement.
	if self.visualItem.requirements then
		local missing = missingTools(self.visualItem.requirements)
		if missing then
			-- Sul personaggio, non in una finestra: e' dove il gioco mette gia'
			-- tutto quello che non si puo' fare, e non ruba il fuoco alla
			-- griglia che si sta guardando.
			local char = self.char or (self.parent and self.parent.char)
			if char and char.setHaloNote then
				char:setHaloNote(getText("UI_IHM_Missing", missing), 220, 180, 90, 300)
			end
			return
		end
	end

	VisualAvatar.select(self)
end

local texture_scissors = getTexture("media/ui/Scissors.png")
local texture_razor    = getTexture("media/ui/Razor.png")
local texture_gel      = getTexture("media/ui/HairGel.png")

function HairAvatar:render()
	VisualAvatar.render(self)
	if self.visualItem.requirements then
		local x_pos = self:getWidth()-20
		local y_pos = 0
		local size = 20
	
		if self.visualItem.requirements.scissors ~= nil then
			if self.visualItem.requirements.scissors then
				self:drawTextureScaled(texture_scissors, x_pos,y_pos, size,size, 1, 1, 1, 1);
			else
				self:drawTextureScaled(texture_scissors, x_pos,y_pos, size,size, 1, 1, 0.5, 0.5);
			end
		end
	
		if self.visualItem.requirements.razor ~= nil then
			-- HACK: Razor only appears for "Bald" which also has scissors so we always draw the razor below regardless.
			if self.visualItem.requirements.razor then
				self:drawTextureScaled(texture_razor, x_pos,y_pos+size, size,size, 1, 1, 1, 1);
			else
				self:drawTextureScaled(texture_razor, x_pos,y_pos+size, size,size, 1, 1, 0.5, 0.5);
			end
		end
	
		if self.visualItem.requirements.hairgel ~= nil then
			if self.visualItem.requirements.hairgel then
				self:drawTextureScaled(texture_gel, x_pos,y_pos, size,size, 1, 1, 1, 1);
			else
				self:drawTextureScaled(texture_gel, x_pos,y_pos, size,size, 1, 1, 0.5, 0.5);
			end
		end
	end
end

function HairAvatar:instantiate()
	VisualAvatar.instantiate(self)
	-- NOTE: Aims at the face.
	self:setZoom(18);
	self:setYOffset(-0.9);
	self:setXOffset(0);
end