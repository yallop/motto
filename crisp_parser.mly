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
%token <int * int * int * int> IPv4
(*
%token <string> STRING
*)
(*FIXME include float?*)
(*FIXME include char?*)

(*Punctuation*)
%token COLON
%token PERIOD
%token SEMICOLON
%token BANG
%token QUES
%token QUESQUES
(*
%token COLONCOLON*)
%token LEFT_R_BRACKET
%token RIGHT_R_BRACKET
%token LEFT_S_BRACKET
%token RIGHT_S_BRACKET
%token LEFT_C_BRACKET
%token RIGHT_C_BRACKET
(*
%token LEFT_A_BRACKET
%token RIGHT_A_BRACKET
*)
%token DASH
(*%token AT
%token PIPE
%token UNDERSCORE
%token ASTERIX
%token HASH
*)
%token GT
%token LT
%token EQUALS
%token SLASH
%token EOF
%token COMMA
%token NL
%token ARR_RIGHT
%token AR_RIGHT

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
%token UNITY
%token FUN
%token IF
%token ELSE
(*%token PERCENT*)
%token PLUS
%token ASTERISK
%token MOD
%token ABS
(*
%token IN
%token DEF
%token CARRY_ON
%token YIELD
%token CASE
%token OF
%token IMPORT
*)
%token AND
%token NOT
%token OR
%token TRUE
%token FALSE
%token TYPE
%token TYPE_INTEGER
%token TYPE_BOOLEAN
%token TYPE_STRING
%token TYPE_RECORD
%token TYPE_VARIANT
%token TYPE_UNIT
%token TYPE_LIST
%token TYPE_IPv4ADDRESS

%token LOCAL
%token GLOBAL
%token ASSIGN
%token LET
%token FOR
%token FROM
%token UNTIL
%token IN
%token EXCEPT
%token ADDRESS_TO_INT
%token INT_TO_ADDRESS


(*Names*)
(*
%token <string> UPPER_ALPHA
%token <string> LOWER_ALPHA
%token <string> NAT_NUM
%token <string> VARIABLE
*)
%token <string> IDENTIFIER

(*NOTE currently semicolons (i.e., sequential composition)
       are implicit in line-breaks;*)
%nonassoc ite
(*%right SEMICOLON*)
%right ASSIGN
%right OR
%right AND
%nonassoc NOT
%nonassoc EQUALS
%nonassoc GT LT
%nonassoc MOD ABS
%nonassoc DASH
%right PLUS
%nonassoc SLASH
%right ASTERISK
%nonassoc ADDRESS_TO_INT
%nonassoc INT_TO_ADDRESS

%start <Crisp_syntax.program> program
%%

program:
  | EOF {[]}
  (*Just a hack to avoid getting compiler warnings about this token
    being unused. This token _can_ be generated by the lexer, but I
    expand it into one or more tokens during a pass that occurs
    between lexing and parsing.*)
  | UNDENTN; p = program {p}
  | NL; p = program {p}
  | e = toplevel_decl; p = program {e :: p}

base_type:
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

(*FIXME include Tuple type*)
single_line_type_def:
  | bt = base_type
    {fun (name : Crisp_syntax.label option) -> bt name}
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

type_def:
  | sltd = single_line_type_def
    {sltd}
  | TYPE_RECORD; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option) -> Crisp_syntax.Record (name, List.rev tl)}
  | TYPE_VARIANT; INDENT; tl = type_lines
    {fun (name : Crisp_syntax.label option) -> Crisp_syntax.Disjoint_Union (name, List.rev tl)}

type_decl:
  | TYPE; type_name = IDENTIFIER; COLON; td = type_def
    { {Crisp_syntax.type_name = type_name;
       Crisp_syntax.type_value = td None} }

channel_type_kind1:
  | from_type = single_line_type_def; SLASH; to_type = single_line_type_def
      {Crisp_syntax.ChannelSingle (from_type None, to_type None)}
  (*NOTE We cannot represents channels of type -/- since they are useless.*)
  | DASH; SLASH; to_type = single_line_type_def
      {Crisp_syntax.ChannelSingle (Crisp_syntax.Empty, to_type None)}
  | from_type = single_line_type_def; SLASH; DASH
      {Crisp_syntax.ChannelSingle (from_type None, Crisp_syntax.Empty)}
  (*NOTE we cannot use the empty type anywhere other than in channels,
    since there isn't any point.*)

channel_type_kind2:
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET;
   LEFT_C_BRACKET; dv = dep_var; RIGHT_C_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, Some dv)
    | _ -> failwith "Malformed type expression: a channel array MUST contain a \
single channel type"}
 | LEFT_S_BRACKET; ctk1 = channel_type_kind1; RIGHT_S_BRACKET
   {match ctk1 with
    | Crisp_syntax.ChannelSingle (from_type, to_type) ->
       Crisp_syntax.ChannelArray (from_type, to_type, None)
    | _ -> failwith "Malformed type expression: a channel array MUST contain a \
single channel type"}

channel_type:
  | ctk1 = channel_type_kind1 {ctk1}
  | ctk2 = channel_type_kind2 {ctk2}

channel: cty = channel_type; chan_name = IDENTIFIER {Crisp_syntax.Channel (cty, chan_name)}

(*There must be at least one channel*)
channels:
  | chan = channel; COMMA; chans = channels {chan :: chans}
  | chan = channel {[chan]}

(*The parameter list may be empty*)
(*FIXME should restrict this to single-line type defs*)
parameters:
  | p = type_line; COMMA; ps = parameters {p :: ps}
  | p = type_line; {[p]}
  | {[]}

(*A list of single-line type defs -- used in the return types of functions*)
singleline_type_list:
  | td = single_line_type_def; COMMA; ps = singleline_type_list {td None :: ps}
  | td = single_line_type_def {[td None]}
  | {[]}

dep_var: id = IDENTIFIER {id}

dep_vars:
  | dvar = dep_var; COMMA; dvars = dep_vars {dvar :: dvars}
  | dvar = dep_var {[dvar]}

(*FIXME allow processes to accept parameters*)
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

(*NOTE the return type doesn't mention expression-level identifiers, which is
  why i'm using "singleline_type_list" there rather than "parameters"*)
(*NOTE a function cannot mention channels in its return type.*)
function_return_type: LEFT_R_BRACKET; ps = singleline_type_list; RIGHT_R_BRACKET
  {Crisp_syntax.FunRetType ps}
function_domain_type:
  | LEFT_R_BRACKET; chans = channels; SEMICOLON; ps = parameters; RIGHT_R_BRACKET
      {Crisp_syntax.FunDomType (chans, ps)}
  | LEFT_R_BRACKET; ps = parameters; RIGHT_R_BRACKET
      {Crisp_syntax.FunDomType ([], ps)}
function_type: fd = function_domain_type; AR_RIGHT; fr = function_return_type
  {Crisp_syntax.FunType (fd, fr)}

state_decl :
  | LOCAL; var = IDENTIFIER; COLON; ty = single_line_type_def; ASSIGN; e = expression
    {Crisp_syntax.LocalState (var, Some (ty None), e)}
  | LOCAL; var = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.LocalState (var, None, e)}
  | GLOBAL; var = IDENTIFIER; COLON; ty = single_line_type_def; ASSIGN; e = expression
    {Crisp_syntax.GlobalState (var, Some (ty None), e)}
  | GLOBAL; var = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.GlobalState (var, None, e)}

states_decl :
  | st = state_decl; NL; sts = states_decl {st :: sts}
  | {[]}

excepts_decl :
  | NL; EXCEPT; ex_id = IDENTIFIER; COLON; e = expression; excs = excepts_decl
    {(ex_id, e) :: excs}
  | {[]}

(*NOTE a process_body is nested between an INDENT and an UNDENT*)
(*NOTE going from Flick to Crisp involves replacing "expression" with "block"*)
process_body:
  sts = states_decl; e = expression; excs = excepts_decl
  {Crisp_syntax.ProcessBody (sts, e, excs)}

expression:
  | TRUE {Crisp_syntax.True}
  | FALSE {Crisp_syntax.False}
  | b1 = expression; AND; b2 = expression
    {Crisp_syntax.And (b1, b2)}
  | b1 = expression; OR; b2 = expression
    {Crisp_syntax.Or (b1, b2)}
  | NOT; b = expression
    {Crisp_syntax.Not b}

  | LEFT_R_BRACKET; e = expression; RIGHT_R_BRACKET {e}
  (*The INDENT-UNDENT combo is a form of bracketing*)
  | INDENT; e = expression; UNDENT {e}
  | UNITY {Crisp_syntax.Unity}
  (*NOTE we determine whether this is a bound variable or a dereference
         during an early pass.*)
  | v = IDENTIFIER {Crisp_syntax.Variable v}
  | IF; be = expression; COLON; e1 = expression; NL; ELSE; COLON; e2 = expression
    %prec ite
    {Crisp_syntax.ITE (be, e1, e2)}
  | IF; be = expression; COLON; e1 = expression; ELSE; COLON; e2 = expression
    %prec ite
    {Crisp_syntax.ITE (be, e1, e2)}
  | v = IDENTIFIER; ASSIGN; e = expression
    {Crisp_syntax.Update (v, e)}

  | LET; v = IDENTIFIER; EQUALS; e = expression
    {Crisp_syntax.LocalDef ((v, None), e)}
  | LET; v = IDENTIFIER; COLON; ty = single_line_type_def; EQUALS; e = expression
    {Crisp_syntax.LocalDef ((v, Some (ty None)), e)}

  | e1 = expression; EQUALS; e2 = expression
    {Crisp_syntax.Equals (e1, e2)}

  | a1 = expression; GT; a2 = expression
    {Crisp_syntax.GreaterThan (a1, a2)}
  | a1 = expression; LT; a2 = expression
    {Crisp_syntax.LessThan (a1, a2)}

  | n = INTEGER
    {Crisp_syntax.Int n}
  | a1 = expression; PLUS; a2 = expression
    {Crisp_syntax.Plus (a1, a2)}
  | a1 = expression; DASH; a2 = expression
    {Crisp_syntax.Minus (a1, a2)}
  | a1 = expression; ASTERISK; a2 = expression
    {Crisp_syntax.Times (a1, a2)}
  | a1 = expression; SLASH; a2 = expression
    {Crisp_syntax.Quotient (a1, a2)}
  | a1 = expression; MOD; a2 = expression
    {Crisp_syntax.Mod (a1, a2)}
  | ABS; a = expression
    {Crisp_syntax.Abs a}

  | address = IPv4
    {Crisp_syntax.IPv4_address address}
  | ADDRESS_TO_INT; e = expression
    {Crisp_syntax.Address_to_int e}
  | INT_TO_ADDRESS; e = expression
    {Crisp_syntax.Int_to_address e}


(*TODO
  Not enabling the following line for the time being -- it's an invititation to
   pack code weirdly.
  | e1 = expression; SEMICOLON; e2 = expression {Crisp_syntax.Seq (e1, e2)}
functiona application
tuple
record
list
variant_exp:
string_exp:
*)

(*FIXME process_body should be like function body except that:
  - functions cannot listen for events.
  - functions cannot specify local state -- they use that of the process.
*)
process_decl: PROC; name = IDENTIFIER; COLON; pt = process_type; INDENT;
  pb = process_body; UNDENT
  {Crisp_syntax.Process (name, pt, pb)}

(*NOTE a process_body is nested between an INDENT and an UNDENT*)
(*NOTE we cannot have empty processes*)
function_body:
  | e = expression; NL; f = function_body {Crisp_syntax.Seq (e, f)}
  | e = expression {e}

function_decl: FUN; name = IDENTIFIER; COLON; ft = function_type; INDENT;
  fb = function_body; UNDENT
    {Crisp_syntax.Function {Crisp_syntax.fn_name = name;
                            Crisp_syntax.fn_params = ft;
                            Crisp_syntax.fn_body = fb}}

toplevel_decl:
  | ty_decl = type_decl {Crisp_syntax.Type ty_decl}
  | process = process_decl {process}
  | funxion = function_decl {funxion}
