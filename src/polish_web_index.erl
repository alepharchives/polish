%% @author Torbjorn Tornkvist tobbe@klarna.com
%%% @copyright (C) 2010, Torbjorn Tornkvist

-module(polish_web_index).

-include("polish.hrl").

-export([main/0,
         title/0,
         layout/0,
	 gen_stats/0,
         inplace_textarea_ok_event/2,
         inplace_textarea_mark_translated_event/1,
	 event/1
	]).

main() ->
     ?AUTH(mainA()).

mainA() ->
    #template { file="./templates/grid.html" }.

title() ->
    "polish".

layout() ->
    {LC, _Action} = Info = get_lang_and_action(),
    Header = polish_common:header(polish_utils:get_language_name(LC)),
    polish_server:unlock_user_keys(),
    #container_12 {
        body=[
              #grid_12 { class = header, body = Header},
              #grid_clear {},
              #grid_12 { body=mk_body(polish_po:get_entries(Info))},
              #grid_clear {},              
              #grid_12 { body=polish_common:footer() }
             ]}.

get_lang_and_action() ->
    LC = maybe_reset_session(),
    Action = 
	case wf:qs("action") of
	    ["search"]            -> get_search_request();
	    ["show_changes"]      -> changes;
	    ["save"]              -> save;
	    ["always_translate"]  -> always_translate;
	    ["submit"]            -> submit;
	    _                     -> po_file
    end,
    {LC, Action}.

get_search_request() ->
    [Str] = wf:qs("search_string"),
    Untrans = get_checkbox_from_qs("untranslated"),
    Trans = get_checkbox_from_qs("translated"),
    Key = get_checkbox_from_qs("key"),
    Value = get_checkbox_from_qs("value"),
    {search, Str, {{translated, Trans}, {untranslated, Untrans},
		   {key, Key}, {value, Value}}}.

get_checkbox_from_qs(K) ->
    case wf:qs(K) of
	[] -> false;
	_  -> true
    end.
    
maybe_reset_session() ->
    case wf:qs("po") of
	[LC] -> maybe_update_lang(LC), LC;
	[]   -> wf:session(offset, 0), wf:session(lang)
    end.

maybe_update_lang(LC) ->
    case wf:session(lang) of
	LC -> ok;
	_  -> wf:session(lang, LC), wf:session(offset, 0)
    end.

%% We don't want those '&nbsp;', thus html_encode=false.
%% However, we do want to escape '<', so some massage is needed.
mk_body([]) ->
    #literal{text="Select a language"};
mk_body({Action, []}) when Action /= changes ->
    #literal{text="No entries found matching the criteria"};
mk_body({Action, Entries}) ->
    TableHeader = [#tableheader{text = "Key"}, #tableheader{text = "Translation"}],
    Rows = [build_row(Key, polish_utils:trim_whitespace(Val)) || {Key,Val} <- Entries],
    [maybe_show_notification(Action), #table{rows = TableHeader ++ Rows}, generate_buttons(Action)].

maybe_show_notification(Action) ->
    case Action of
	save -> 
	    #label { text = "Your translation has been saved for submission.", class="notification"};
	always_translate -> 
	    #label { text = "Your selection hasa been marked as always translated.",
		     class="notification"};
	submit ->
	    #label { text = "Your translations have been submitted.",
		     class="notification"};
	_    -> []
    end.

s(K,"", S2)          -> ibox(K,"__empty__", S2);
s(K,header_info, S2) -> ibox(K,"__empty__", S2);
s(K,S, S2)           -> ibox(K,m(S), S2).

ibox(K,S, NotScapedS) ->
    #inplace_textarea { text=S , text_textarea= NotScapedS,
			tag=K , html_encode=false}.

m(header_info) -> "";
m([$<|T]) -> [$&,$l,$t,$;|m(T)];
m([H|T])  -> [H|m(T)];
m([])     -> [].

build_row(Key, Val) ->
    #tablerow { cells = [#tablecell { text = m(Key),
				     class = "msgid",
				     html_encode = false },
			 #tablecell { body = s(Key, Val, Val),
				      html_encode = false,
				      class = "msgval"}]}.
    
     

generate_buttons(Action) when Action =:= po_file;
			      Action =:= save;
			      Action =:= always_translate;
			      Action =:= search;
			      Action =:= submit ->
    Next = [#button{text = "Next", id = "next_button",
		   postback = next_entries}],
    Previous = case wf:session(offset) of
		   undefined     -> [];
		   O when O =< 0 -> [];
		   O when O > 0  ->
		       [#button{text = "Previous", id = "prev_button", 
				postback =previous_entries}]
	       end,
    Previous ++ Next;
generate_buttons(changes) ->
    #button{text = "Submit", class = "button",
	    postback = write}.

gen_stats() ->
    {LC, _A} = get_lang_and_action(),
    {Total, Untrans, Trans, Editors} = polish_po:get_stats(LC),
    Editors2 = 
	lists:foldl(
	  fun({Editor, Amount}, Acc) ->
		  [#value{text = Editor++": "++integer_to_list(Amount)}|Acc]
	  end, [], Editors),
    Editors3 = case Editors2 of
		   [] -> [#value{text = "Nobody"}];
		   _  -> Editors2
	       end,
    [ #label{text = "Number of keys: "},
      #value{text = integer_to_list(Total)},
      #br{},
      #label{text = "Untranslated: "},
      #value{text = integer_to_list(Untrans)},
      #br{},
      #label{text = "Unsubmitted translations: "},
      #value{text = integer_to_list(Trans)},
      #br{},
      #label{text = "Currently translating: "}] ++ Editors3.


%% Save translation
inplace_textarea_ok_event(Key, Val0) ->
    {Lang, Action} = get_lang_and_action(),
    Orig = get_original(list_to_atom(Lang), Key, Action),
    Val = to_latin1(polish_utils:restore_whitespace(Orig, polish_utils:trim_whitespace(Val0))),
    case polish_po:check_correctness(Key, Val) of
	ok ->
	    polish_server:unlock_user_keys(),
	    polish_server:insert([{Key,Val}], list_to_atom(wf:session(lang))),
	    wf:redirect("?action=save");
	{error, Msg} ->
	    {error, Msg, Val0}
    end.   

%% Mark as always translated
inplace_textarea_mark_translated_event(Key) ->
    LCa = list_to_atom(wf:session(lang)),
    polish_server:mark_as_always_translated(LCa, Key),
    wf:redirect("?action=always_translate").

%% The stupid browser persist to send utf-8 characters...
to_latin1(Str) ->
    case binary_to_list(<< <<C>> || <<C/utf8>> <= list_to_binary(Str) >>) of
        []   -> Str;
        Lstr -> Lstr
    end.

%% called when Next button pressed
event(next_entries) ->
    wf:session(offset, wf:session(offset) + 20),
    wf:redirect("");
event(previous_entries) ->
    wf:session(offset, wf:session(offset) - 20),
    wf:redirect("");
event(write) ->
    polish_po:write(),
    LC = wf:session(lang),
    wf:redirect("?action=submit&po="++LC).

get_original(Lang, Key, changes) ->
    Saved = polish_server:get_changes(Lang),
    {Key, Orig} = lists:keyfind(Key, 1, Saved),
    Orig;
get_original(Lang, Key, _Action) ->
    polish_server:locked_key_orig(Lang, Key).
