%%% @author Nadia Mohedano-Troyano <nadia@klarna.com>
%%% @copyright (C) 2010, Nadia Mohedano-Troyano
-module(login_SUITE).
-compile(export_all).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("../include/polish.hrl").

suite() ->
    [].

all() ->
    [start_authentication
     , bad_authentication_user_not_allowed
     , bad_authentication_wrong_openid_format
     , finish_authentication
    ].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% I N I T S
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_per_suite(Config) ->
    polish_test_lib:start_polish_for_test(),
    Config.

init_per_testcase(finish_authentication, Config) ->
    polish_test_lib:write_fake_login_data(),
    Config;
init_per_testcase(_TestCase, Config) ->
    Config.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% E N D S
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end_per_suite(_Config) ->
    ok.

end_per_testcase(finish_authentication, _Config) ->
    polish_test_lib:clean_fake_login_data(),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% T E S T   C A S E S
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_authentication(_Config) ->
    ClaimedId = "jordi-chacon.myopenid.com",
    {Code, Headers, _ResponseJSON} = polish_test_lib:send_http_request(
    				       get, [{autoredirect, false}],
				       "/login?claimed_id=" ++ ClaimedId,
    				       ?JSON, headers),
    ?assertEqual(?FOUND, Code),
    Url = polish_utils:url_decode(?lkup("location", Headers)),
    check_identity_in_url(Url, ClaimedId),
    check_assoc_handle_in_url(Url),
    ok.

check_identity_in_url(Url, ClaimedId) ->
    {match, [_, {Start, Length}]} = re:run(Url, "openid.identity=(.*)&",
					   [ungreedy]),
    Identity = lists:sublist(Url, Start+1, Length),
    ?assertEqual({match, [{7, 25}]}, re:run(Identity, ClaimedId)).

check_assoc_handle_in_url(Url) ->
    {match, [_, {Start, Length}]} = re:run(Url, "openid.assoc_handle=(.*)&",
					  [ungreedy]),
    AuthId = lists:sublist(Url, Start+1, Length),
    ?assertMatch([_,_,_,_,_,_],  polish_server:read_user_auth(AuthId)).

finish_authentication(_Config) ->
    {Code, Headers, _ResponseJSON} = polish_test_lib:send_http_request(
				       get, [{autoredirect, false}],
				       get_fake_redirect_url(), ?JSON, headers),
    ?assertEqual(?FOUND, Code),
    ?assertEqual(polish_utils:build_url(),
		 polish_utils:url_decode(?lkup("location", Headers))),
    ?assertEqual("auth=HMAC-SHA14ce7ff3bchZ2eA; Version=1",
		 ?lkup("set-cookie", Headers)),
    ok.

get_fake_redirect_url() ->
    "/login?action=auth&openid.assoc_handle=%7BHMAC-SHA1%7D%"
	"7B4ce7ff3b%7D%7BchZ2eA%3D%3D%7D&openid.identity=http%3A%2F%2Fjor"
	"di-chacon.myopenid.com%2F&openid.mode=id_res&openid.op_endpoint="
	"http%3A%2F%2Fwww.myopenid.com%2Fserver&openid.response_nonce=201"
	"0-11-20T17%3A02%3A53ZnO85X2&openid.return_to=http%3A%2F%2F192.16"
	"8.10.249%3A8282%2Fauth&openid.sig=2l%2BSVA4gD7Faa16RzWY6VBvdk%2F"
	"U%3D&openid.signed=assoc_handle%2Cidentity%2Cmode%2Cop_endpoint%"
	"2Cresponse_nonce%2Creturn_to%2Csigned".

bad_authentication_user_not_allowed(_Config) ->
    ClaimedId = "nadia.myopenid.com",
    {Code, Headers, ResponseJSON} = polish_test_lib:send_http_request(
    				       get, [{autoredirect, false}],
				       "/login?claimed_id=" ++ ClaimedId,
    				       ?JSON, headers),
    ?assertEqual(?OK, Code),
    ?assertEqual(none, proplists:lookup("location", Headers)),
    {struct, Response} = mochijson2:decode(ResponseJSON),
    polish_test_lib:assert_fields_from_response(
      [{"login", "error"}, {"reason", "user not allowed"}], Response),
    ok.

bad_authentication_wrong_openid_format(_Config) ->
    ClaimedId = "jordi-chacon",
    {Code, Headers, ResponseJSON} = polish_test_lib:send_http_request(
    				       get, [{autoredirect, false}],
				       "/login?claimed_id=" ++ ClaimedId,
    				       ?JSON, headers),
    ?assertEqual(?OK, Code),
    ?assertEqual(none, proplists:lookup("location", Headers)),
    {struct, Response} = mochijson2:decode(ResponseJSON),
    polish_test_lib:assert_fields_from_response(
      [{"login", "error"}, {"reason", "wrong openid format"}], Response),
    ok.
