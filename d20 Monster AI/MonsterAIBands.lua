local mod = dmhub.GetModLoading()

--Hand-written tactics and speech for key monsters of the 5.5e bestiary.
--Each band is a tactic profile (MonsterAITactics.lua), the lines its members
--say (in the Codex's voice: short, punchy, in character), and where the
--generic planner is not enough, moves of its own.
--
--Speech events: start, attack, spell, area, kill, hurt, dying, retreat,
--opportunity, legendary, charge, heal. A creature only speaks if it knows a
--language; lines in a band are said in its own language unless the band
--names one.

local Rules = MonsterAIRules

---------------------------------------------------------------------------
--Goblins: hit and run, Nimble Escape out of reach after every stab.
---------------------------------------------------------------------------

local GOBLINS = {"Goblin*"}

MonsterAI.RegisterTactic{
	monsters = GOBLINS,
	focus = "weakest",
	retreatBelow = 0.5,
	fleeBelow = 0.2,
}

MonsterAI.RegisterSpeech{
	monsters = GOBLINS,
	lines = {
		start = {"Get 'em!", "Stab 'em!", "Shinies!"},
		attack = {"Stab!", "Hee hee!", "Gotcha!", "Poke!"},
		kill = {"Got one!", "Mine now!", "Hee hee hee!"},
		retreat = {"Run away!", "Can't catch me!", "Nyah!"},
		hurt = {"Ow!", "No fair!"},
		dying = {"Not fair!", "Ow ow ow!"},
		opportunity = {"Nope!", "Stab!"},
	},
}

MonsterAI.RegisterMove{
	id = "Nimble Escape: hit and run",
	description = "After attacking in melee, a goblin uses Nimble Escape to Disengage and falls back, keeping its shortbow in range.",
	category = "Bonus Action",
	monsters = GOBLINS,
	maxScore = 0.8,
	score = function(ai, token, ctx)
		if not ai.turn.actionUsed or ai.turn.bonusUsed or not Rules.HasAction(token, "bonus") then
			return 0
		end
		if MonsterAI.MovementLeftFeet(token) < dmhub.unitsPerSquare then
			return 0
		end
		if not MonsterAIGeneric.EnemyAdjacentAt(ai, token, ctx, token.loc) then
			return 0
		end
		if MonsterAIGeneric.BonusBasic(ctx, "disengage") == nil then
			return 0
		end
		return 0.8, {description = "Nimble Escape (Disengage) and fall back"}
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.bonusUsed = true
		ai.turn.escaped = true
		ai:Speak(token, "retreat")
		MonsterAIGeneric.TakeBasic(ai, token, ctx, "disengage", true)
		local fresh = MonsterAIGeneric.BuildContext(ai, token)
		local paths = ai:CalculateMovementPaths(token)
		local info = MonsterAIGeneric.RetreatLoc(ai, token, fresh, paths, MonsterAIGeneric.LongestRange(fresh))
		if info ~= nil then
			ai:MoveToken(token, info.loc)
		end
	end,
}

---------------------------------------------------------------------------
--Kobolds and wolves: pack hunters.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Kobold*"},
	packTactics = true,
	focus = "weakest",
	fleeBelow = 0.25,
}

MonsterAI.RegisterSpeech{
	monsters = {"Kobold*"},
	lines = {
		start = {"Intruders!", "For the dragon!"},
		attack = {"Many of us!", "Surround!", "Yip yip!"},
		kill = {"Dragon be pleased!"},
		retreat = {"Too strong!", "Flee!"},
		dying = {"For the dragon...!"},
	},
}

MonsterAI.RegisterTactic{
	monsters = {"Wolf", "Dire Wolf", "Worg", "Winter Wolf", "Jackal", "Hyena", "Giant Hyena", "Death Dog"},
	packTactics = true,
	style = "melee",
	focus = "weakest",
}

MonsterAI.RegisterSpeech{
	monsters = {"Worg", "Winter Wolf"},
	lines = {
		start = {"Hunt!", "Fresh meat!"},
		attack = {"Drag it down!", "Bleed!"},
		kill = {"Feast!"},
	},
}

---------------------------------------------------------------------------
--Hobgoblins: a disciplined line. They do not break formation to chase.
---------------------------------------------------------------------------

local HOBGOBLINS = {"Hobgoblin*"}

MonsterAI.RegisterTactic{
	monsters = HOBGOBLINS,
	focus = "weakest",
	provokePenalty = 10,
}

MonsterAI.RegisterSpeech{
	monsters = HOBGOBLINS,
	lines = {
		start = {"Form up!", "Advance!", "For the legion!"},
		attack = {"Strike!", "Hold the line!", "Press them!"},
		kill = {"Next!", "Victory!"},
		hurt = {"Close ranks!"},
		dying = {"For the legion!", "No retreat!"},
		opportunity = {"Hold!"},
	},
}

---------------------------------------------------------------------------
--Bugbears: ambushers that pick on the weak.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Bugbear*"},
	style = "melee",
	focus = "weakest",
}

MonsterAI.RegisterSpeech{
	monsters = {"Bugbear*"},
	lines = {
		start = {"Surprise!", "Heh."},
		attack = {"Crush!", "Squish!"},
		kill = {"Too easy."},
		dying = {"Hrrk!"},
	},
}

---------------------------------------------------------------------------
--Gnolls and ghouls: they go for the fallen.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Gnoll*"},
	finishDowned = true,
	style = "melee",
}

MonsterAI.RegisterSpeech{
	monsters = {"Gnoll*"},
	lines = {
		start = {"Feed!", "Blood!"},
		attack = {"Rip!", "Hungry!"},
		kill = {"Feast!", "More!"},
		dying = {"Yeenoghu!"},
	},
}

MonsterAI.RegisterTactic{
	monsters = {"Ghoul", "Ghast"},
	finishDowned = true,
	style = "melee",
}

MonsterAI.RegisterSpeech{
	monsters = {"Ghoul", "Ghast"},
	lines = {
		start = {"Fresh meat!", "Warm flesh!"},
		attack = {"Hungry!", "Feed!"},
		kill = {"Mine!"},
	},
}

---------------------------------------------------------------------------
--Mindless undead: they shamble at whatever is nearest.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Zombie", "Ogre Zombie", "Skeleton", "Minotaur Skeleton", "Warhorse Skeleton"},
	finishDowned = true,
	provokePenalty = 0,
}

MonsterAI.RegisterSpeech{
	monsters = {"Zombie", "Ogre Zombie", "Skeleton", "Minotaur Skeleton", "Warhorse Skeleton"},
	silent = true,
}

---------------------------------------------------------------------------
--Bandits, pirates and toughs: in it for the money, and gone when it goes bad.
---------------------------------------------------------------------------

local OUTLAWS = {"Bandit*", "Pirate*", "Tough*"}

MonsterAI.RegisterTactic{
	monsters = OUTLAWS,
	fleeBelow = 0.25,
}

MonsterAI.RegisterTactic{
	monsters = {"Bandit Captain", "Pirate Captain", "Tough Boss"},
	fleeBelow = 0.15,
	focus = "weakest",
}

MonsterAI.RegisterSpeech{
	monsters = OUTLAWS,
	lines = {
		start = {"Your money or your life!", "Get 'em, lads!", "Easy pickings!"},
		attack = {"Run 'em through!", "Hand it over!", "Take that!"},
		kill = {"Check his pockets!", "Who's next?"},
		retreat = {"Not worth it!", "I'm out!", "Every man for himself!"},
		hurt = {"Ow, you'll pay!"},
		dying = {"Curse you!"},
		opportunity = {"Not so fast!"},
	},
}

---------------------------------------------------------------------------
--Guards, knights and soldiers.
---------------------------------------------------------------------------

local SOLDIERS = {"Guard*", "Knight", "Warrior*", "Gladiator", "Noble", "Berserker"}

MonsterAI.RegisterTactic{
	monsters = SOLDIERS,
	provokePenalty = 8,
}

MonsterAI.RegisterSpeech{
	monsters = SOLDIERS,
	lines = {
		start = {"Halt!", "Stand down!", "To arms!"},
		attack = {"Have at you!", "For the realm!", "Yield!"},
		kill = {"Stay down!"},
		hurt = {"Hold fast!"},
		dying = {"I yield... never!"},
		opportunity = {"Not so fast!"},
	},
}

---------------------------------------------------------------------------
--Cultists: fanatics to the last.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Cultist*"},
	finishDowned = true,
}

MonsterAI.RegisterSpeech{
	monsters = {"Cultist*"},
	lines = {
		start = {"For the master!", "Heretics!"},
		attack = {"Blood for the dark one!", "Die, unbeliever!"},
		spell = {"Darkness take you!", "Behold!"},
		kill = {"An offering!"},
		dying = {"The master... awaits...", "I am rewarded!"},
	},
}

---------------------------------------------------------------------------
--Priests: keep their side standing.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Priest", "Priest Acolyte", "Druid"},
	focus = "weakest",
	retreatBelow = 0.4,
}

MonsterAI.RegisterSpeech{
	monsters = {"Priest", "Priest Acolyte", "Druid"},
	lines = {
		start = {"The gods are with us!"},
		heal = {"Be healed!", "Rise!", "Stand fast!"},
		spell = {"By my faith!", "Begone!"},
		attack = {"Repent!"},
		dying = {"Forgive me..."},
	},
}

---------------------------------------------------------------------------
--Mages and liches: stay out of reach, blink away, burn the crowd.
---------------------------------------------------------------------------

local CASTERS = {"Mage", "Mage Apprentice", "Archmage", "Lich"}

MonsterAI.RegisterTactic{
	monsters = CASTERS,
	style = "ranged",
	focus = "weakest",
	retreatBelow = 1.0,
	adjacentPenalty = 6,
	friendlyFire = 2,
}

MonsterAI.RegisterSpeech{
	monsters = {"Mage", "Mage Apprentice", "Archmage"},
	lines = {
		start = {"Fools!", "You dare?"},
		spell = {"Burn!", "Begone!", "Witness true power!"},
		area = {"Burn!", "All of you!"},
		attack = {"Pathetic!"},
		retreat = {"Not so close!", "Ha!"},
		kill = {"Next!"},
		hurt = {"You'll regret that!"},
		dying = {"Impossible!"},
	},
}

MonsterAI.RegisterSpeech{
	monsters = {"Lich"},
	lines = {
		start = {"Kneel.", "You came to die."},
		spell = {"Death comes!", "Wither!"},
		area = {"Your souls are mine!", "Perish!"},
		attack = {"Pitiful."},
		kill = {"Another soul."},
		hurt = {"Insolence!"},
		dying = {"I will return!"},
		legendary = {"Too slow."},
	},
}

---------------------------------------------------------------------------
--Dragons: open with the breath weapon whenever it catches a crowd.
---------------------------------------------------------------------------

local DRAGONS = {"*Dragon", "*Dragon Wyrmling", "Half-Dragon"}

MonsterAI.RegisterTactic{
	monsters = DRAGONS,
	style = "melee",
	focus = "weakest",
	friendlyFire = 1.0,
	provokePenalty = 4,
}

MonsterAI.RegisterSpeech{
	monsters = DRAGONS,
	lines = {
		start = {"Insects!", "You dare?", "Kneel!"},
		area = {"Perish!", "Feel my wrath!", "Ashes!"},
		attack = {"Pathetic!", "Die!"},
		kill = {"Who's next?", "Delicious."},
		hurt = {"You will pay for that!"},
		dying = {"Impossible!", "This... cannot be!"},
		legendary = {"Too slow!", "Behind you."},
	},
}

MonsterAI.RegisterMove{
	id = "Breath Weapon",
	description = "A dragon breathes whenever its breath weapon is recharged and would catch two or more enemies.",
	category = "Action",
	monsters = DRAGONS,
	maxScore = 1.05,
	score = function(ai, token, ctx)
		if ai.turn.actionUsed or not Rules.HasAction(token, "action") then
			return 0
		end
		local best, bestPlan = 0, nil
		local locs = MonsterAIGeneric.CandidateLocs(ai, token, ctx)
		for _,profile in ipairs(ctx.byKind["action"] or {}) do
			if profile.affordable and Rules.IsArea(profile) and string.find(profile.lname, "breath", 1, true) then
				for i,info in ipairs(locs) do
					if i > 6 then
						break
					end
					local penalty = MonsterAIGeneric.ProvokersAt(ai, token, ctx, info.loc)*(ctx.tactics.provokePenalty or 4)
					for _,aim in ipairs(ctx.targets) do
						local value, caught, shape, count = MonsterAIGeneric.EvaluateArea(ai, token, ctx, profile, info.loc, aim)
						if value ~= nil and count >= 2 and value - penalty > best then
							best = value - penalty
							bestPlan = {
								kind = "action",
								loc = info.loc,
								cost = info.cost,
								area = {profile = profile, aim = aim, caught = caught, count = count},
								value = best,
							}
						end
					end
				end
			end
		end
		if bestPlan == nil then
			return 0
		end
		bestPlan.description = MonsterAIGeneric.DescribePlan(token, bestPlan)
		return 1.05, bestPlan
	end,
	execute = function(ai, token, plan, ctx)
		ai.turn.actionUsed = true
		MonsterAIGeneric.ExecuteOffense(ai, token, plan, ctx)
	end,
}

---------------------------------------------------------------------------
--Giants, ogres and trolls.
---------------------------------------------------------------------------

local BRUTES = {"Ogre", "*Giant", "Ettin", "Troll"}

MonsterAI.RegisterTactic{
	monsters = BRUTES,
	style = "melee",
	provokePenalty = 3,
}

MonsterAI.RegisterSpeech{
	monsters = BRUTES,
	lines = {
		start = {"Smash!", "Little people!"},
		attack = {"Smash!", "Squish!", "Puny!"},
		kill = {"Ha! Flat!"},
		hurt = {"Grr! Hurt!"},
		dying = {"Nooo!"},
		charge = {"Smash!"},
	},
}

---------------------------------------------------------------------------
--Vampires: patient and cruel.
---------------------------------------------------------------------------

MonsterAI.RegisterTactic{
	monsters = {"Vampire", "Vampire Spawn"},
	focus = "weakest",
}

MonsterAI.RegisterSpeech{
	monsters = {"Vampire", "Vampire Spawn"},
	lines = {
		start = {"Welcome.", "Come closer."},
		attack = {"Your blood is mine!", "So warm..."},
		kill = {"Delicious."},
		hurt = {"You will suffer for that."},
		dying = {"Not... like this!"},
		legendary = {"Too slow."},
	},
}

---------------------------------------------------------------------------
--Fiends.
---------------------------------------------------------------------------

local DEMONS = {"Balor", "Glabrezu", "Hezrou", "Marilith", "Nalfeshnee", "Vrock", "Dretch", "Quasit"}

MonsterAI.RegisterTactic{
	monsters = DEMONS,
	finishDowned = true,
	friendlyFire = 0.5,
}

MonsterAI.RegisterSpeech{
	monsters = DEMONS,
	lines = {
		start = {"Despair!", "Mortals!"},
		attack = {"Suffer!", "Rend!", "Bleed!"},
		kill = {"More!", "Delicious agony!"},
		dying = {"I will return!"},
	},
}

local DEVILS = {"*Devil", "Imp", "Pit Fiend", "Erinyes", "Lemure"}

MonsterAI.RegisterTactic{
	monsters = DEVILS,
	focus = "weakest",
	provokePenalty = 10,
}

MonsterAI.RegisterSpeech{
	monsters = DEVILS,
	lines = {
		start = {"Sign here.", "A bargain?"},
		attack = {"Obey!", "Your soul is forfeit!"},
		kill = {"Contract fulfilled."},
		hurt = {"Insolent mortal!"},
		dying = {"This is not the end!"},
	},
}
