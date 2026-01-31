using Godot;
using System;
using System.Threading.Tasks;

public partial class GDSync : Node
{
	private static Node GDSYNC;
	private static Node GDSYNC_SHARP;

	public static event Action Connected;
	public static event Action<int> ConnectionFailed; //error
	public static event Action Disconnected;
	public static event Action<int> ClientIDChanged; //error
	public static event Action<string> LobbyCreated;
	public static event Action<string, int> LobbyCreationFailed; //lobby name | error
	public static event Action<string> LobbyJoined; //lobby name
	public static event Action<string, int> LobbyJoinFailed; //lobby name | error
	public static event Action<string, Variant> LobbyDataChanged; //key | value
	public static event Action<string, Variant> LobbyTagChanged; //key | value
	public static event Action<int> ClientJoined; //client ID
	public static event Action<int> ClientLeft; //client ID
	public static event Action<int, string, Variant> PlayerDataChanged; //client ID | key | value
	public static event Action<Godot.Collections.Array> LobbiesReceived; //lobbies
	public static event Action<bool, int> HostChanged; //is host | host ID
	public static event Action<string, Godot.Collections.Array> SyncedEventTriggered; //event name | parameters

	public override void _Ready()
	{
		GDSYNC = GetNode("/root/GDSync");
		GDSYNC_SHARP = this;

		GDSYNC.Connect("connected", Callable.From(() => { Connected?.Invoke(); }));
		GDSYNC.Connect("connection_failed", Callable.From((int error) => { ConnectionFailed?.Invoke(error); }));
		GDSYNC.Connect("disconnected", Callable.From(() => { Disconnected?.Invoke(); }));
		GDSYNC.Connect("client_id_changed", Callable.From((int ownID) => { ClientIDChanged?.Invoke(ownID); }));
		GDSYNC.Connect("lobby_created", Callable.From((string lobbyName) => { LobbyCreated?.Invoke(lobbyName); }));
		GDSYNC.Connect("lobby_creation_failed", Callable.From((string lobbyName, int error) => { LobbyCreationFailed?.Invoke(lobbyName, error); }));
		GDSYNC.Connect("lobby_joined", Callable.From((string lobbyName) => { LobbyJoined?.Invoke(lobbyName); }));
		GDSYNC.Connect("lobby_join_failed", Callable.From((string lobbyName, int error) => { LobbyJoinFailed?.Invoke(lobbyName, error); }));
		GDSYNC.Connect("lobby_data_changed", Callable.From((string key, Variant value) => { LobbyDataChanged?.Invoke(key, value); }));
		GDSYNC.Connect("lobby_tag_changed", Callable.From((string key, Variant value) => { LobbyTagChanged?.Invoke(key, value); }));
		GDSYNC.Connect("client_joined", Callable.From((int clientID) => { ClientJoined?.Invoke(clientID); }));
		GDSYNC.Connect("client_left", Callable.From((int clientID) => { ClientLeft?.Invoke(clientID); }));
		GDSYNC.Connect("player_data_changed", Callable.From((int clientID, string key, Variant value) => { PlayerDataChanged?.Invoke(clientID, key, value); }));
		GDSYNC.Connect("lobbies_received", Callable.From((Godot.Collections.Array lobbies) => { LobbiesReceived?.Invoke(lobbies); }));
		GDSYNC.Connect("host_changed", Callable.From((bool isHost, int hostID) => { HostChanged?.Invoke(isHost, hostID); }));
		GDSYNC.Connect("synced_event_triggered", Callable.From((string eventName, Godot.Collections.Array parameters) => { SyncedEventTriggered?.Invoke(eventName, parameters); }));
	}




	// General functions -----------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region General Functions

	public static void StartMultiplayer()
	{
		GDSYNC.Call("start_multiplayer");
	}

	public static void StopMultiplayer()
	{
		GDSYNC.Call("stop_multiplayer");
	}

	public static bool IsActive()
	{
		return (bool)GDSYNC.Call("is_active");
	}

	public static int GetClientID()
	{
		return (int)GDSYNC.Call("get_client_id");
	}

	public static int GetSenderID()
	{
		return (int)GDSYNC.Call("get_sender_id");
	}

	public static Godot.Collections.Array GetAllClients()
	{
		return (Godot.Collections.Array)GDSYNC.Call("get_all_clients");
	}

	public static bool IsHost()
	{
		return (bool)GDSYNC.Call("is_host");
	}

	public static int GetHost()
	{
		return (int)GDSYNC.Call("get_host");
	}

	public static void SyncVar(Node node, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var", node, variableName, reliable);
	}

	public static void SyncVarOn(int clientID, Node node, string variableName, bool reliable = true)
	{
		GDSYNC.Call("sync_var_on", clientID, node, variableName, reliable);
	}

	public static void CallFunc(Callable callable, Godot.Collections.Array parameters = null, bool reliable = true)
	{
		GDSYNC.Call("call_func", callable, parameters, reliable);
	}

	public static void CallFuncOn(int clientID, Callable callable, Godot.Collections.Array parameters = null, bool reliable = true)
	{
		GDSYNC.Call("call_func_on", clientID, callable, parameters, reliable);
	}

	public static void CreateSyncedEvent(string eventName, float delay = 1.0f, Godot.Collections.Array parameters = null)
	{
		if (parameters == null) parameters = new Godot.Collections.Array();
		GDSYNC.Call("create_synced_event", eventName, delay, parameters);
	}

	public static Node MultiplayerInstantiate(PackedScene scene, Node parent, bool syncStartingChanges = true, string[] excludedProperties = null, bool replicateOnJoin = true)
	{
		if (excludedProperties == null) excludedProperties = new string[0];
		return (Node)GDSYNC.Call("multiplayer_instantiate", scene, parent, syncStartingChanges, excludedProperties, replicateOnJoin);
	}
	#endregion






	// Security & safety functions -------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Security & Safety Functions

	public static void SetProtectionMode(bool protectionEnabled)
	{
		GDSYNC.Call("set_protection_mode", protectionEnabled);
	}

	public static void ExposeNode(Node node)
	{
		GDSYNC.Call("expose_node", node);
	}

	public static void HideNode(Node node)
	{
		GDSYNC.Call("hide_node", node);
	}

	public static void ExposeFunction(Callable callable)
	{
		GDSYNC.Call("expose_func", callable);
	}

	public static void HideFunction(Callable callable)
	{
		GDSYNC.Call("hide_function", callable);
	}

	public static void ExposeVar(Node node, string variableName)
	{
		GDSYNC.Call("expose_var", node, variableName);
	}

	public static void HideVar(Node node, string variableName)
	{
		GDSYNC.Call("hide_var", node, variableName);
	}
	#endregion


	// Node ownership --------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Node Ownership

	public static void SetGDSyncOwner(Node node, int owner)
	{
		GDSYNC.Call("set_gdsync_owner", node, owner);
	}

	public static void ClearGDSyncOwner(Node node)
	{
		GDSYNC.Call("clear_gdsync_owner", node);
	}

	public static int GetGDSyncOwner(Node node)
	{
		return (int)GDSYNC.Call("get_gdsync_owner", node);
	}

	public static bool IsGDSyncOwner(Node node)
	{
		return (bool)GDSYNC.Call("is_gdsync_owner", node);
	}

	public static void ConnectGDSyncOwnerChanged(Node node, Callable callable)
	{
		GDSYNC.Call("connect_gdsync_owner_changed", node, callable);
	}

	public static void DisconnectGDSyncOwnerChanged(Node node, Callable callable)
	{
		GDSYNC.Call("disconnect_gdsync_owner_changed", node, callable);
	}
	#endregion


	// Lobby functions -------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Lobby Functions

	public static void GetPublicLobbies()
	{
		GDSYNC.Call("get_public_lobbies");
	}

	public static void CreateLobby(string name, string password = "", bool isPublic = true, int playerLimit = 0, Godot.Collections.Dictionary tags = null, Godot.Collections.Dictionary data = null)
	{
		if (tags == null) tags = new Godot.Collections.Dictionary();
		if (data == null) data = new Godot.Collections.Dictionary();
		GDSYNC.Call("create_lobby", name, password, isPublic, playerLimit, tags, data);
	}

	public static void JoinLobby(string name, string password = "")
	{
		GDSYNC.Call("join_lobby", name, password);
	}

	public static void CloseLobby()
	{
		GDSYNC.Call("close_lobby");
	}

	public static void OpenLobby()
	{
		GDSYNC.Call("open_lobby");
	}

	public static void SetLobbyVisibility(bool isPublic)
	{
		GDSYNC.Call("set_lobby_visibility", isPublic);
	}

	public static void LeaveLobby()
	{
		GDSYNC.Call("leave_lobby");
	}

	public static int GetLobbyPlayerCount()
	{
		return (int)GDSYNC.Call("get_lobby_player_count");
	}

	public static string GetLobbyName()
	{
		return (string)GDSYNC.Call("get_lobby_name");
	}

	public static int GetLobbyPlayerLimit()
	{
		return (int)GDSYNC.Call("get_lobby_player_limit");
	}

	public static void SetLobbyTag(string key, Variant value)
	{
		GDSYNC.Call("set_lobby_tag", key, value);
	}

	public static void EraseLobbyTag(string key)
	{
		GDSYNC.Call("erase_lobby_tag", key);
	}

	public static bool HasLobbyTag(string key)
	{
		return (bool)GDSYNC.Call("has_lobby_tag", key);
	}

	public static Variant GetLobbyTag(string key, Variant defaultValue = new Variant())
	{
		return GDSYNC.Call("get_lobby_tag", key, defaultValue);
	}

	public static Godot.Collections.Dictionary GetAllLobbyTags()
	{
		return (Godot.Collections.Dictionary)GDSYNC.Call("get_all_lobby_tags");
	}

	public static void SetLobbyData(string key, Variant value)
	{
		GDSYNC.Call("set_lobby_data", key, value);
	}

	public static void EraseLobbyData(string key)
	{
		GDSYNC.Call("erase_lobby_data", key);
	}

	public static bool HasLobbyData(string key)
	{
		return (bool)GDSYNC.Call("has_lobby_data", key);
	}

	public static Variant GetLobbyData(string key, Variant defaultValue = new Variant())
	{
		return GDSYNC.Call("get_lobby_data", key, defaultValue);
	}

	public static Godot.Collections.Dictionary GetAllLobbyData()
	{
		return (Godot.Collections.Dictionary)GDSYNC.Call("get_all_lobby_data");
	}
	#endregion

	// Player functions ------------------------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Player Functions

	public static void SetPlayerData(string key, Variant value)
	{
		GDSYNC.Call("set_player_data", key, value);
	}

	public static void ErasePlayerData(string key)
	{
		GDSYNC.Call("erase_player_data", key);
	}

	public static Variant GetLobbyData(int clientID, string key, Variant defaultValue = new Variant())
	{
		return GDSYNC.Call("get_player_data", clientID, key, defaultValue);
	}

	public static Godot.Collections.Dictionary GetAllPlayerData(int clientID)
	{
		return (Godot.Collections.Dictionary)GDSYNC.Call("get_all_player_data", clientID);
	}

	public static void SetPlayerUsername(string username)
	{
		GDSYNC.Call("set_player_username", username);
	}
	#endregion

	// Accounts & Persistent Data Storage ------------------------------------------
	// *****************************************************************************
	// -----------------------------------------------------------------------------
	#region Accounts & Persistent Data Storage

	public static async Task<ACCOUNT_CREATION_RESPONSE_CODE> CreateAccount(string email, string username, string password)
	{
		var asyncRequest = GDSYNC.Call("create_account", email, username, password).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (ACCOUNT_CREATION_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<ACCOUNT_DELETION_RESPONSE_CODE> DeleteAccount(string email, string password)
	{
		var asyncRequest = GDSYNC.Call("delete_account", email, password).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (ACCOUNT_DELETION_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<ACCOUNT_VERIFICATION_RESPONSE_CODE> VerifyAccount(string email, string code, float validTime = 86400)
	{
		var asyncRequest = GDSYNC.Call("verify_account", email, code, validTime).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (ACCOUNT_VERIFICATION_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<RESEND_VERIFICATION_RESPONSE_CODE> ResendVerificationEmail(string email, string password)
	{
		var asyncRequest = GDSYNC.Call("resend_verification_code", email, password).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (RESEND_VERIFICATION_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> IsVerified(string username = "")
	{
		var asyncRequest = GDSYNC.Call("is_verified", username).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> Login(string email, string password, float validTime = 86400)
	{
		var asyncRequest = GDSYNC.Call("login", email, password, validTime).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> LoginFromSession(float validTime = 86400)
	{
		var asyncRequest = GDSYNC.Call("login_from_session", validTime).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<LOGOUT_RESPONSE_CODE> Logout()
	{
		var asyncRequest = GDSYNC.Call("logout").AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (LOGOUT_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<CHANGE_USERNAME_RESPONSE_CODE> ChangeAccountUsername(string newUsername)
	{
		var asyncRequest = GDSYNC.Call("change_account_username", newUsername).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (CHANGE_USERNAME_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<CHANGE_PASSWORD_RESPONSE_CODE> ChangeAccountPassword(string email, string password, string newPassword)
	{
		var asyncRequest = GDSYNC.Call("change_account_password", email, password, newPassword).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (CHANGE_PASSWORD_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<REQUEST_PASSWORD_RESET_RESPONSE_CODE> RequestPasswordReset(string email)
	{
		var asyncRequest = GDSYNC.Call("request_account_password_reset", email).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (REQUEST_PASSWORD_RESET_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<RESET_PASSWORD_RESPONSE_CODE> ResetPassword(string email, string resetCode, string newPassword)
	{
		var asyncRequest = GDSYNC.Call("reset_password", email, resetCode, newPassword).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (RESET_PASSWORD_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<REPORT_USER_RESPONSE_CODE> ReportAccount(string usernameToReport, string report)
	{
		var asyncRequest = GDSYNC.Call("report_account", usernameToReport, report).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (REPORT_USER_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<SET_PLAYER_DOCUMENT_RESPONSE_CODE> SetPlayerDocument(string path, Godot.Collections.Dictionary document, bool externallyVisible = false)
	{
		var asyncRequest = GDSYNC.Call("set_player_document", path, document, externallyVisible).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (SET_PLAYER_DOCUMENT_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<SET_EXTERNAL_VISIBLE_RESPONSE_CODE> SetExternallyVisible(string path, bool externallyVisible = false)
	{
		var asyncRequest = GDSYNC.Call("set_external_visible", path, externallyVisible).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (SET_EXTERNAL_VISIBLE_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> GetPlayerDocument(string path)
	{
		var asyncRequest = GDSYNC.Call("get_player_document", path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> HasPlayerDocument(string path)
	{
		var asyncRequest = GDSYNC.Call("has_player_document", path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> BrowsePlayerCollection(string path)
	{
		var asyncRequest = GDSYNC.Call("browse_player_collection", path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<DELETE_PLAYER_DOCUMENT_RESPONSE_CODE> DeletePlayerDocument(string path)
	{
		var asyncRequest = GDSYNC.Call("delete_player_document", path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (DELETE_PLAYER_DOCUMENT_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> GetExternalPlayerDocument(string externalUsername, string path)
	{
		var asyncRequest = GDSYNC.Call("get_external_player_document", externalUsername, path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> HasExternalPlayerDocument(string externalUsername, string path)
	{
		var asyncRequest = GDSYNC.Call("has_external_player_document", externalUsername, path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> BrowseExternalPlayerCollection(string externalUsername, string path)
	{
		var asyncRequest = GDSYNC.Call("browse_external_player_collection", externalUsername, path).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> HasLeaderboard(string leaderboard)
	{
		var asyncRequest = GDSYNC.Call("has_leaderboard", leaderboard).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> GetLeaderboards()
	{
		var asyncRequest = GDSYNC.Call("get_leaderboards").AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> BrowseLeaderboard(string leaderboard, int pageSize, int page)
	{
		var asyncRequest = GDSYNC.Call("browse_leaderboard", leaderboard, pageSize, page).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<Godot.Collections.Dictionary> GetLeaderboardScore(string leaderboard, string username)
	{
		var asyncRequest = GDSYNC.Call("get_leaderboard_score", leaderboard, username).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (Godot.Collections.Dictionary)result[0];
	}

	public static async Task<SUBMIT_SCORE_RESPONSE_CODE> SubmitScore(string leaderboard, int score)
	{
		var asyncRequest = GDSYNC.Call("submit_score", leaderboard, score).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (SUBMIT_SCORE_RESPONSE_CODE)(int)result[0];
	}

	public static async Task<SUBMIT_SCORE_RESPONSE_CODE> DeleteScore(string leaderboard)
	{
		var asyncRequest = GDSYNC.Call("delete_score", leaderboard).AsGodotObject();
		var result = await GDSYNC_SHARP.ToSignal(asyncRequest, "completed");
		return (SUBMIT_SCORE_RESPONSE_CODE)(int)result[0];
	}
	#endregion



	#region enums
	private enum CONNECTION_STATUS
	{
		LOBBY_SWITCH = -1,
		DISABLED,
		FINDING_LB,
		PINGING_SERVERS,
		CONNECTING,
		CONNECTED,
		CONNECTION_SECURED,
	}

	private enum PACKET_CHANNEL
	{
		SETUP,
		SERVER,
		RELIABLE,
		UNRELIABLE,
		INTERNAL,
	}

	private enum PACKET_VALUE
	{
		PADDING,
		CLIENT_REQUESTS,
		SERVER_REQUESTS,
		INTERNAL_REQUESTS,
	}

	private enum REQUEST_TYPE
	{
		VALIDATE_KEY,
		SECURE_CONNECTION,
		MESSAGE,
		SET_VARIABLE,
		CALL_FUNCTION,
		SET_VARIABLE_CACHED,
		CALL_FUNCTION_CACHED,
		CACHE_NODE_PATH,
		ERASE_NODE_PATH_CACHE,
		CACHE_NAME,
		ERASE_NAME_CACHE,
		SET_MC_OWNER,
		CREATE_LOBBY,
		JOIN_LOBBY,
		LEAVE_LOBBY,
		OPEN_LOBBY,
		CLOSE_LOBBY,
		SET_LOBBY_TAG,
		ERASE_LOBBY_TAG,
		SET_LOBBY_DATA,
		ERASE_LOBBY_DATA,
		SET_LOBBY_VISIBILITY,
		SET_LOBBY_PLAYER_LIMIT,
		SET_LOBBY_PASSWORD,
		GET_PUBLIC_LOBBIES,
		SET_PLAYER_USERNAME,
		SET_PLAYER_DATA,
		ERASE_PLAYER_DATA,
		SET_CONNECT_TIME,
		SET_SETTING,
		CREATE_ACCOUNT,
		DELETE_ACCOUNT,
		VERIFY_ACCOUNT,
		LOGIN,
		LOGIN_FROM_SESSION,
		LOGOUT,
		SET_PLAYER_DOCUMENT,
		HAS_PLAYER_DOCUMENT,
		GET_PLAYER_DOCUMENT,
		DELETE_PLAYER_DOCUMENT,
	}

	private enum MESSAGE_TYPE
	{
		CRITICAL_ERROR,
		CLIENT_ID_RECEIVED,
		CLIENT_KEY_RECEIVED,
		INVALID_PUBLIC_KEY,
		SET_NODE_PATH_CACHE,
		ERASE_NODE_PATH_CACHE,
		SET_NAME_CACHE,
		ERASE_NAME_CACHE,
		SET_MC_OWNER,
		HOST_CHANGED,
		LOBBY_CREATED,
		LOBBY_CREATION_FAILED,
		LOBBY_JOINED,
		SWITCH_SERVER,
		LOBBY_JOIN_FAILED,
		LOBBIES_RECEIVED,
		LOBBY_DATA_RECEIVED,
		LOBBY_DATA_CHANGED,
		LOBBY_TAGS_CHANGED,
		PLAYER_DATA_RECEIVED,
		PLAYER_DATA_CHANGED,
		CLIENT_JOINED,
		CLIENT_LEFT,
		SET_CONNECT_TIME,
		SET_SENDER_ID,
		SET_DATA_USAGE,
	}

	private enum SETTING
	{
		API_VERSION,
		USE_SENDER_ID,
	}

	private enum DATA
	{
		REQUEST_TYPE,
		NAME,
		VALUE,
		TARGET_CLIENT = 3,
	}

	private enum LOBBY_DATA
	{
		NAME = 1,
		PASSWORD = 2,
		PARAMETERS = 1,
		VISIBILITY = 1,
		VALUE = 2,
	}

	private enum FUNCTION_DATA
	{
		NODE_PATH = 1,
		NAME = 2,
		PARAMETERS = 4
	}

	private enum VAR_DATA
	{
		NODE_PATH = 1,
		NAME = 2,
		VALUE = 4
	}

	private enum MESSAGE_DATA
	{
		TYPE = 1,
		VALUE = 2,
		ERROR = 3,
		VALUE2 = 3,
	}

	public enum CRITICAL_ERROR
	{
		LOBBY_DATA_FULL,
		LOBBY_TAGS_FULL,
		PLAYER_DATA_FULL,
		REQUEST_TOO_LARGE,
	}

	private enum INTERNAL_MESSAGE
	{
		LOBBY_UPDATED,
		LOBBY_DELETED,
		REQUEST_LOBBIES,
		INCREASE_DATA_USAGE,
	}

	public enum CONNECTION_FAILED
	{
		INVALID_PUBLIC_KEY,
		TIMEOUT,
	}

	public enum LOBBY_CREATION_ERROR
	{
		LOBBY_ALREADY_EXISTS,
		NAME_TOO_SHORT,
		NAME_TOO_LONG,
		PASSWORD_TOO_LONG,
		TAGS_TOO_LARGE,
		DATA_TOO_LARGE,
		ON_COOLDOWN,
	}

	public enum LOBBY_JOIN_ERROR
	{
		LOBBY_DOES_NOT_EXIST,
		LOBBY_IS_CLOSED,
		LOBBY_IS_FULL,
		INCORRECT_PASSWORD,
		DUPLICATE_USERNAME,
	}

	public enum NODE_REPLICATION_SETTINGS
	{
		INSTANTIATOR,
		SYNC_STARTING_CHANGES,
		EXCLUDED_PROPERTIES,
		SCENE,
		TARGET,
		ORIGINAL_PROPERTIES,
	}

	public enum NODE_REPLICATION_DATA
	{
		ID,
		CHANGED_PROPERTIES,
	}

	public enum ACCOUNT_CREATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		STORAGE_FULL,
		INVALID_EMAIL,
		INVALID_USERNAME,
		EMAIL_ALREADY_EXISTS,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		PASSWORD_TOO_SHORT,
		PASSWORD_TOO_LONG,
	}

	public enum ACCOUNT_DELETION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
	}

	public enum RESEND_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		VERIFICATION_DISABLED,
		ON_COOLDOWN,
		ALREADY_VERIFIED,
		EMAIL_OR_PASSWORD_INCORRECT,
		BANNED,
	}

	public enum ACCOUNT_VERIFICATION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		INCORRECT_CODE,
		CODE_EXPIRED,
		ALREADY_VERIFIED,
		BANNED,
	}

	public enum IS_VERIFIED_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		USER_DOESNT_EXIST,
	}

	public enum LOGIN_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		EXPIRED_SESSION,
		BANNED,
	}

	public enum LOGOUT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum CHANGE_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_OR_PASSWORD_INCORRECT,
		NOT_VERIFIED,
		BANNED,
	}

	public enum CHANGE_USERNAME_RESPONSE_CODE
	{

		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		ON_COOLDOWN,
		USERNAME_ALREADY_EXISTS,
		USERNAME_TOO_SHORT,
		USERNAME_TOO_LONG,
		INVALID_USERNAME
	}

	public enum RESET_PASSWORD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		EMAIL_OR_CODE_INCORRECT,
		CODE_EXPIRED,
	}

	public enum REQUEST_PASSWORD_RESET_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		ON_COOLDOWN,
		EMAIL_DOESNT_EXIST,
		BANNED,
	}

	public enum SET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
	}

	public enum GET_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum BROWSE_PLAYER_COLLECTION_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum SET_EXTERNAL_VISIBLE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}


	public enum HAS_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
	}

	public enum DELETE_PLAYER_DOCUMENT_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		DOESNT_EXIST,
	}

	public enum REPORT_USER_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		REPORT_TOO_LONG,
		TOO_MANY_REPORTS,
		USER_DOESNT_EXIST,
	}

	public enum SUBMIT_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		STORAGE_FULL,
		LEADERBOARD_DOESNT_EXIST
	}

	public enum DELETE_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	public enum GET_LEADERBOARDS_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	public enum HAS_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN
	}

	public enum BROWSE_LEADERBOARD_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST
	}

	public enum GET_LEADERBOARD_SCORE_RESPONSE_CODE
	{
		SUCCESS,
		NO_RESPONSE_FROM_SERVER,
		DATA_CAP_REACHED,
		RATE_LIMIT_EXCEEDED,
		NO_DATABASE,
		NOT_LOGGED_IN,
		LEADERBOARD_DOESNT_EXIST,
		USER_DOESNT_EXIST
	}
	#endregion
}
