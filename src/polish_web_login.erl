%% @author Torbjorn Tornkvist tobbe@klarna.com
%%% @copyright (C) 2010, Torbjorn Tornkvist

-module(polish_web_login).

-include("polish.hrl").

-export([main/0,
         title/0,
	 event/1,
	 body/0
	]).

main() ->
    #template { file="./templates/login.html" }.

title() ->
    "POlish - The PO file manager".

body() ->
    Action = wf:qs("action"),
    BadLoginMsg = get_bad_login_msg(Action),
    B = [#textbox { class = "claimed_id", id = claimed_id, text="" },
	 #br{},
	 #button{class = "button", id = "auth", text = "Login", postback = claimed_id}],
    wf:wire("claimed_id", #event { type = keypress, keycode = 13,
                             postback = claimed_id, 
                             delegate = ?MODULE}),
    B ++ BadLoginMsg.

get_bad_login_msg(["bad_login"]) ->
    [#label{class="error_login", text="Login error"}];
get_bad_login_msg(_) ->
    [].

event(claimed_id) ->
    try
        [ClaimedId0] = wf:qs(claimed_id),
	ClaimedId    = eopenid_lib:http_path_norm(ClaimedId0),
        HostName     = polish_deps:get_env(hostname, polish:hostname()),
        Port         = polish_deps:get_env(port, polish:default_port()),
        URL          = "http://"++HostName++":"++polish:i2l(Port),
        Dict0        = eopenid_lib:foldf(
                         [eopenid_lib:in("openid.return_to", URL++"/auth"),
                          eopenid_lib:in("openid.trust_root", URL)
                         ], eopenid_lib:new()),

        {ok,Dict1}   = eopenid_v1:discover(ClaimedId, Dict0),
        {ok,Dict2}   = eopenid_v1:associate(Dict1),
        {ok, Url}    = eopenid_v1:checkid_setup(Dict2),

        wf:session(eopenid_dict, Dict2),
        wf:redirect(Url)
    catch      
        _:Error ->
            io:format("ERROR=~p~n",[Error]),
            wf:redirect("login?action=bad_login")
    end;
event(E) ->
    io:format("E=~p~n",[E]).
    


