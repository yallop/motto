(*
   Parser spec for Crisp
   Nik Sultana, Cambridge University Computer Lab, January 2015

   Target parser-generator: menhir 20140422
*)

(*FIXME add terminator indicators for strings and lists, and gap indicators for
  lists. this should also allow us to encode lists of lists etc.*)
(*TODO add type variables?*)
(*TODO add (first-order) functions?*)

(*Native value interpretations*)
%token <int> INTEGER (*FIXME is OCaml's "int" of the precision we want to support?*)
%token <string> STRING
%token <bool> BOOLEAN
(*FIXME include float?*)
(*FIXME include char?*)
(*FIXME need to include unit value*)

(*Punctuation*)
%token COLON
%token SEMICOLON
%token BANG
%token QUESTION
%token PERIOD
%token COLONCOLON
%token LEFT_R_BRACKET
%token RIGHT_R_BRACKET
%token LEFT_S_BRACKET
%token RIGHT_S_BRACKET
%token LEFT_C_BRACKET
%token RIGHT_C_BRACKET
%token LEFT_A_BRACKET
%token RIGHT_A_BRACKET
%token AT
%token PIPE
%token PLUS
%token UNDERSCORE
%token DASH
%token ASTERIX
%token SLASH
%token EOF
%token COMMA
%token NL
%token HASH
%token EQUALS
%token GT
%token LT
%token ARR_RIGHT
%token MINUS

(*Since we're relying on the offside rule for scoping, code blocks aren't
  explicitly delimited as in e.g., Algol-68-style languages.*)
%token <int> UNDENTN
(*The lexer will produce UNDENTN tokens, then a filter (sitting between
  the lexer and parser) will expand these into UNDENT tokens.*)
%token INDENT
%token UNDENT
(* NOTE that INDENT also means that a NL occurred (before the indent)
        and UNDENT also means that a newline occurred (before the first indent).
        UNDENTN n means that NL followed by UNDENTs occurred.
*)

(*Reserved words*)
%token PROC
%token IF
%token ELSE
%token IN
%token DEF
%token CARRY_ON
%token YIELD
%token TYPE
%token TYPE_INTEGER
%token TYPE_BOOLEAN
%token TYPE_STRING
%token TYPE_RECORD
%token TYPE_VARIANT
%token TYPE_UNIT
%token TYPE_LIST
%token CASE
%token OF
%token AND
%token NOT
%token OR
%token IMPORT

(*Names*)
%token <string> UPPER_ALPHA
%token <string> LOWER_ALPHA
%token <string> NAT_NUM
%token <string> VARIABLE
%token <string> IDENTIFIER

%start <Crisp_syntax.program> program
%%

program:
  | EOF {[]}
  | NL; p = program {p}
  | e = toplevel_decl; p = program {e :: p}

base_type:
(*TODO include the empty type!*)
  | TYPE_STRING {fun name -> Crisp_syntax.String name}
  | TYPE_INTEGER {fun name -> Crisp_syntax.Integer name}
  | TYPE_BOOLEAN {fun name -> Crisp_syntax.Boolean name}
  | TYPE_UNIT {fun name -> Crisp_syntax.Unit name}

(*FIXME need to include termination conditions for lists and string*)
(*FIXME include byte-order annotations*)
(*The kinds of type declarations we want to parse:

   type alias_example: string

   type record_example: record
     l1 : string
     l2 : integer

   type variant_example: variant
     l1 : string
     l2 : integer

   type compound_example: variant
     l1 : integer
     l2 : record
       l3 : string
       l4 : integer
     l5 : integer
*)

type_line:
  | value_name = IDENTIFIER; COLON; td = type_def {td (Some value_name)}

type_lines:
  | tl = type_line; NL; rest = type_lines { tl :: rest }
  | tl = type_line; UNDENT { [tl] }

type_def:
  | bt = base_type
    {fun (name : Crisp_syntax.label option) -> bt name}
  | TYPE_RECORD; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option) -> Crisp_syntax.Record (name, List.rev tl)}
  | TYPE_VARIANT; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option) -> Crisp_syntax.Disjoint_Union (name, List.rev tl)}
  | TYPE_LIST; LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET; td = type_def
    {fun (name : Crisp_syntax.label option) ->
       Crisp_syntax.List (name, td None, Some dv)}
  | TYPE_LIST; td = type_def
    {fun (name : Crisp_syntax.label option) ->
       Crisp_syntax.List (name, td None, None)}
  | TYPE; type_name = IDENTIFIER
    {fun (name : Crisp_syntax.label option) -> Crisp_syntax.UserDefinedType (name, type_name)}
  | LEFT_S_BRACKET; td = type_def; RIGHT_S_BRACKET
    {fun (name : Crisp_syntax.label option) ->
       Crisp_syntax.List (name, td None, None)}
  | LEFT_S_BRACKET; td = type_def; RIGHT_S_BRACKET; LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET
    {fun (name : Crisp_syntax.label option) ->
       Crisp_syntax.List (name, td None, Some dv)}

type_decl:
  | TYPE; type_name = IDENTIFIER; COLON; td = type_def
    { {Crisp_syntax.type_name = type_name;
       Crisp_syntax.type_value = td None} }

(*NOTE this is quite powerful, since we could have structured types specified
  at this point, but that wouldn't be a very neat thing to do, so i might
  forbid by blocking it during one of the early compiler passes.*)
channel_type_kind1:
  | from_type = type_def; SLASH; to_type = type_def
      {Crisp_syntax.ChannelSingle (from_type None, to_type None)}
  (*NOTE We cannot represents channels of type -/- since they are useless.*)
  | MINUS; SLASH; to_type = type_def
      {Crisp_syntax.ChannelSingle (Crisp_syntax.Empty, to_type None)}
  | from_type = type_def; SLASH; MINUS
      {Crisp_syntax.ChannelSingle (from_type None, Crisp_syntax.Empty)}
  (*NOTE we cannot use the empty type anywhere other than in channels,
    since there isn't any point.*)

channel_type_kind2:
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET;
   LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, Some dv)}
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, None)}

channel_type:
  | ctk1 = channel_type_kind1 {ctk1}
  | ctk2 = channel_type_kind2 {ctk2}

channel: cty = channel_type; chan_name = IDENTIFIER {Crisp_syntax.Channel (cty, chan_name)}

(*There must be at least one channel*)
channels:
  | chan = channel; COMMA; chans = channels {chan :: chans}
  | chan = channel {[chan]}

dep_var: id = IDENTIFIER {id}

dep_vars:
  | dvar = dep_var; COMMA; dvars = dep_vars {dvar :: dvars}
  | dvar = dep_var {[dvar]}

(*NOTE that an independent_process_type may contain free variables -- this is
  picked up during type-checking, not during parsing.*)
independent_process_type: LEFT_R_BRACKET; chans = channels; RIGHT_R_BRACKET
  {chans}
dependent_process_type: LEFT_C_BRACKET; dvars = dep_vars; RIGHT_C_BRACKET; ARR_RIGHT;
  ipt = independent_process_type
  {Crisp_syntax.ProcessType (dvars, ipt)}
process_type:
  | chans = independent_process_type {Crisp_syntax.ProcessType ([], chans)}
  | dpt = dependent_process_type {dpt}


(*TODO include process definition body*)
process_decl: PROC; name = IDENTIFIER; COLON; pt = process_type
  {Crisp_syntax.Process (name, pt)}

toplevel_decl:
  | ty_decl = type_decl {Crisp_syntax.Type ty_decl}
  | process = process_decl {process}
