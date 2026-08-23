--- @class lobby 
--- @field maxGameDetailsLength any 
--- @field maxGameTitleLength any 
--- @field maxGamePasswordLength any 
--- @field gamesRevision any 
--- @field games any 
--- @field createdGameId any 
--- @field createdGameIdAge any 
--- @field deletedGameId any 
lobby = {}

--- CreateGame: Creates a new game. Options may include backend ("local", "durableobjects", "durableobjects-staging", or "firebase"), create(gameid), and error(message).
--- @param options? table
--- @return nil
function lobby:CreateGame(options)
	-- dummy implementation for documentation purposes only
end

--- PromoteLocalGame: Copies a local game to Cloudflare, verifies the online copy, and then deletes the local copy. Set staging=true to target the staging Worker; release is the default.
--- @param options table Options containing gameid, optional staging, progress(status, pct), and complete(success, newGameid, error).
--- @return nil
function lobby:PromoteLocalGame(options)
	-- dummy implementation for documentation purposes only
end

--- EnterGame
--- @param gameid string
--- @return nil
function lobby:EnterGame(gameid)
	-- dummy implementation for documentation purposes only
end

--- LookupGame
--- @param gameid any
--- @param callback any
--- @return nil
function lobby:LookupGame(gameid, callback)
	-- dummy implementation for documentation purposes only
end

--- JoinGame
--- @param gameid string
--- @return nil
function lobby:JoinGame(gameid)
	-- dummy implementation for documentation purposes only
end
