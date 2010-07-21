-module(ddfs).

-include("config.hrl").

-export([new_blob/4, tags/2, get_tag/4, update_tag/4,
         update_tag_delayed/4, replace_tag/5, delete/3]).

-spec new_blob(node(), string(), non_neg_integer(), [node()]) ->
    'invalid_name' | 'too_many_replicas' | {'ok', [string()]} | _.
new_blob(Host, Blob, Replicas, Exclude) ->
    validate(Blob, fun() ->
        Obj = [Blob, "$", ddfs_util:timestamp()],
        gen_server:call(Host, {new_blob, Obj, Replicas, Exclude})
    end).

-spec tags(node(), binary()) -> 'timeout' | {'ok', [binary()]}.
tags(Host, Prefix) ->
    case catch gen_server:call(Host, {get_tags, safe}, ?NODEOP_TIMEOUT) of
        {'EXIT', {timeout, _}} ->
            timeout;
        {ok, Tags} ->
            {ok, if Prefix =:= <<>> ->
                Tags;
            true ->
                [T || T <- Tags, ddfs_util:startswith(T, Prefix)]
            end};
        E -> E
    end.

-spec get_tag(node(), string(), atom() | string(), ddfs_tag:token() | 'internal') ->
    'invalid_name' | 'notfound' | 'deleted' | 'unknown_attribute'
    | {'ok', binary()} | {'error', _}.
get_tag(Host, Tag, Attrib, Token) ->
    validate(Tag, fun() ->
        case gen_server:call(Host,
                {tag, {get, Attrib, Token}, list_to_binary(Tag)}, ?NODEOP_TIMEOUT) of
            TagData when is_binary(TagData) ->
                {ok, TagData};
            E -> E
        end
    end).

-spec update_tag(node(), string(), [binary()], ddfs_tag:token()) -> _.
update_tag(Host, Tag, Urls, Token) ->
    tagop(Host, Tag, {update, Urls, Token}).

-spec update_tag_delayed(node(), string(), [binary()], ddfs_tag:token()) -> _.
update_tag_delayed(Host, Tag, Urls, Token) ->
    tagop(Host, Tag, {delayed_update, Urls, Token}).

-spec replace_tag(node(), string(), atom(), [binary()], ddfs_tag:token()) -> _.
replace_tag(Host, Tag, Field, Value, Token) ->
    tagop(Host, Tag, {put, Field, Value, Token}).

-spec delete(node(), string(), ddfs_tag:token() | 'internal') -> _.
delete(Host, Tag, Token) ->
    tagop(Host, Tag, {delete, Token}).

-spec tagop(node(), string(), _) -> _.
tagop(Host, Tag, Op) ->
   validate(Tag, fun() ->
        case gen_server:call(Host,
                {tag, Op, list_to_binary(Tag)}, ?TAG_UPDATE_TIMEOUT) of
            {ok, Ret} ->
                {ok, Ret};
            E ->
                E
        end
    end).

-spec validate(string(), fun(()-> T)) -> T.
validate(Name, Fun) ->
    case ddfs_util:is_valid_name(Name) of
        false ->
            {error, invalid_name};
        true ->
            case catch Fun() of
                {'EXIT', {timeout, _}} ->
                    {error, timeout};
                Ret ->
                    Ret
            end
    end.


