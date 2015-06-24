(*
   High-level transformations applied to the source program.
   Nik Sultana, Cambridge University Computer Lab, February 2015
*)

open General
open State
open Crisp_syntax
open Naasty
open Data_model
open Type_infer (*FIXME currently unused*)

let expand_includes (include_directories : string list) (p : Crisp_syntax.program) =
  let rec expand_includes' (p : Crisp_syntax.program) =
    List.fold_right (fun decl acc ->
      match decl with
      | Include source_file ->
        (*FIXME take include_directories into account; currently this info is
                unused.*)
        (*FIXME when all the include directories have been exhausted and the
                file hasn't been found yet, then try the current directory.*)
        let inclusion =
          Crisp_parse.parse source_file
          |> List.rev
        in expand_includes' inclusion @ acc
      | _ -> decl :: acc) p []
  in List.rev (expand_includes' p)

(*Gather declaration information from a program, and encode in the state.*)
let collect_decl_info (st : State.state) (p : Crisp_syntax.program) : State.state =
  List.fold_right (fun decl st' ->
    match decl with
    | Function {fn_name; fn_params; _} ->
(*FIXME check that have distinct parameter names, otherwise using named
  parameters could be confusing*)
      { st' with crisp_funs = (fn_name, fn_params) :: st'.crisp_funs }
    | Type _
    | Process _ -> st' (*NOTE currently we ignore type and process declarations*)
    | Include _ ->
      failwith "Inclusions should have been expanded before reaching this point.")
    p st

(*Given a program whose Includes have been expanded out, separate out the
  declarations of types, processes, and functions -- but keep their relative
  order stable. That is, if we rewrite the program to contain the types, then
  the functions, then the processes, then all existing dependencies should
  continue to be satisified. (Originally, types, functions and processes can be
  given in any order as long as usual scoping rules are satisfied.)
  Then chop source file into different units, collecting declarations of the
  same kind*)
let split_declaration_kinds (p : Crisp_syntax.program) :
  Crisp_project.compilation_unit * Crisp_project.compilation_unit *
  Crisp_project.compilation_unit =
  List.fold_right (fun decl (types, functions, processes) ->
    match decl with
    | Type _ -> (decl :: types, functions, processes)
    | Process _ -> (types, functions, decl :: processes)
    | Function _ -> (types, decl :: functions, processes)
    | Include _ ->
      failwith "Inclusions should have been expanded before reaching this point.")
    p ([], [], [])
  |> (fun (types, functions, processes) ->
    ({ Crisp_project.name = "types";
       Crisp_project.content = List.rev types },
     { Crisp_project.name = "functions";
       Crisp_project.content = List.rev functions },
     { Crisp_project.name = "processes";
       Crisp_project.content = List.rev processes }))

(*Every type becomes 2 compilation units in NaaSty: a header file and a code
  file.*)
let translate_type_compilation_unit (st : state)
      (types_unit : Crisp_project.compilation_unit) :
  Naasty_project.compilation_unit list * state =
  fold_couple ([], st)
    (fun (st' : state) (decl : Crisp_syntax.toplevel_decl)
      (cunits : Naasty_project.compilation_unit list) ->
       let name = Crisp_syntax_aux.name_of_type decl in
       let (translated, st'') =
         Translation.naasty_of_flick_program ~st:st' [decl] in
       let module Data_model_instance =
         Instance(Data_model_consts.Values(
         struct
           let datatype_name = name
           let ty = Crisp_syntax_aux.the_ty_of_decl decl
         end)) in
       let (type_data_model_instance, st''') =
         fold_map ([], st'') (fun st scheme ->
           Naasty_aux.instantiate_type true scheme.identifiers st scheme.type_scheme)
           Data_model_instance.instantiate_data_model in
       let header_unit =
         {Naasty_project.name = name;
          Naasty_project.unit_type = Naasty_project.Header;
          (*FIXME currently hardcoded, but this list of inclusions could be
                  extended based on an analysis of the code in the module.*)
          Naasty_project.inclusions =
            ["<stdint.h>";
             "<iostream>";
             "<assert.h>";
             "<exception>";
             "\"TaskBuffer.h\"";
             "\"applications/NaasData.h\""];
          Naasty_project.content =
            [Naasty_aux.add_fields_to_record (the_single translated)
               type_data_model_instance]
         } in
       let (function_data_model_instance, st4) =
         fold_map ([], st''') (fun st scheme ->
           Naasty_aux.instantiate_function true scheme.identifiers st
             scheme.function_scheme)
           Data_model_instance.instantiate_data_model in
       let cpp_unit =
         {Naasty_project.name = name;
          Naasty_project.unit_type = Naasty_project.Cpp;
          (*FIXME currently hardcoded, but this list of inclusions could be
                  extended based on an analysis of the code in the module.*)
          Naasty_project.inclusions =
            ["\"" ^ Naasty_project.filename_of_compilationunit header_unit ^ "\"";
             "\"LinearBuffer.h\"";
             "<iostream>";
             "\"utils/ReadWriteData.h\"";
             "\"applications/NaasData.h\""];
          Naasty_project.content =
            List.map (fun fn -> Fun_Decl fn) function_data_model_instance
         }
       in (header_unit :: cpp_unit :: cunits, st4))
    types_unit.Crisp_project.content

let translate_function_compilation_unit (st : state)
      (functions_unit : Crisp_project.compilation_unit) :
  Naasty_project.compilation_unit list * state =
  fold_map ([], st)
    (fun (st' : state) (flick_f : Crisp_syntax.toplevel_decl) ->
       let name = "functions"(*FIXME extract name?*) in
       let (translated, st'') =
         Translation.naasty_of_flick_program ~st:st' [flick_f] in
       ({Naasty_project.name = name;
         Naasty_project.unit_type = Naasty_project.Cpp;
         Naasty_project.inclusions =
           [(*FIXME*)];
         Naasty_project.content = translated
        }, (*FIXME generate header file together with this .cpp*)
        st''))
    functions_unit.Crisp_project.content

(*FIXME currently ignoring processes*)
let translate_serialise_stringify
  (st : State.state)
  ((types_unit, functions_unit, processes_unit) :
     Crisp_project.compilation_unit *
     Crisp_project.compilation_unit *
     Crisp_project.compilation_unit) =
  let stringify_compilation_unit (st : state) (cu : Naasty_project.compilation_unit) =
    (Naasty_project.filename_of_compilationunit cu,
     Naasty_project.string_of_compilationunit ~st_opt:(Some st) cu) in
  let (translated_type_units, st') =
    translate_type_compilation_unit st types_unit in
  let (translated_function_units, st'') =
    translate_function_compilation_unit st' functions_unit in
  if !Config.cfg.Config.debug then State_aux.state_to_str true st'' |> print_endline;
  List.map (stringify_compilation_unit st'')
    (translated_type_units @ translated_function_units)

let compile (cfg : Config.configuration ref) (program : Crisp_syntax.program) : (string * string) list =
  expand_includes !cfg.Config.include_directories program
  |> selfpair
  |> apfst (collect_decl_info State.initial_state)
  |> apsnd (split_declaration_kinds)
  (*FIXME Functorise to take backend-specific code as parameter*)
  |> uncurry translate_serialise_stringify
