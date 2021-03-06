(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

open Common

module Ast = Ast_js

module Db = Database_code

module HC = Highlight_code

module T = Parser_js

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

(* We build the full database in multiple steps as some
 * operations need the information computed globally by the
 * previous step:
 * 
 * - collect all definitions and their file
 * - collect all uses, updating the count number of the
 *   corresponding entity (if it's used in a different file)
 * 
 * Currently the analysis is just lexical-based (yes I know, I am
 * ridiculous) so there is some ambiguity when we find a use.
 * We don't know to which precise entity it corresponds to
 * (to be precise would require to resolve module name).
 * 
 *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)
let hcommon_methods = Common.hashset_of_list [
  "construct";
  "getInstance";
]
let is_common_method s = 
  Hashtbl.mem hcommon_methods s


let mk_entity ~root ~hcomplete_name_of_info info categ =

  let s = Ast.str_of_info info in
  (* when using frameworks like Javelin/JX, the defs are
   * actually in strings, as in JX.install("MyClass", { ... });
   *)
  let s = Ast.remove_quotes_if_present s in

  (*pr2 (spf "mk_entity %s" s);*)

  let l = Ast.line_of_info info in
  let c = Ast.col_of_info info in
  
  let name = s in
  let fullname = 
    try Hashtbl.find hcomplete_name_of_info info +> snd
    with Not_found -> ""
  in
              
  { Database_code.
    e_name = name;
    e_fullname = 
      if fullname <> name then fullname else "";
    e_file = 
      Ast.file_of_info info +> 
        Common.filename_without_leading_path root;
    e_pos = { Common.l = l; Common.c = c };
    e_kind = Database_code.entity_kind_of_highlight_category_def categ;

    (* filled in step 2 *)
    e_number_external_users = 0;
    (* TODO *)
    e_good_examples_of_use = [];

    (* TODO *)
    e_properties = [];
  }


(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let compute_database ?(verbose=false) files_or_dirs = 

  (* when we want to merge this database with the db of another language
   * like PHP, the other database may use realpath for the path of the files
   * so we want to behave the same.
   *)
  let files_or_dirs = files_or_dirs +> List.map Common.realpath in

  let root = Common.common_prefix_of_files_or_dirs files_or_dirs in
  pr2 (spf "generating JS db_light with root = %s" root);

  let files = Lib_parsing_js.find_js_files_of_dir_or_files files_or_dirs in
  let dirs = files +> List.map Filename.dirname +> Common.uniq_eff in

  (* step1: collecting definitions *)
  let (hdefs: (string, Db.entity) Hashtbl.t) = Hashtbl.create 1001 in

  (* remember the position of the def so avoid some false positives
   * when looking for uses.
   *)
  let (hdefs_pos: (Ast.tok, bool) Hashtbl.t) = Hashtbl.create 1001 in

  files +> List.iter (fun file ->
    if verbose then pr2 (spf "PHASE 1: %s" file);

    let (ast2, _stat) = Parse_js.parse file in

    let ast = Parse_js.program_of_program2 ast2 in
    let hcomplete_name_of_info = 
      Class_js.extract_complete_name_of_info ast 
    in

    ast2 +> List.iter (fun (ast, (_str, toks)) ->
      let prefs = Highlight_code.default_highlighter_preferences in

      Highlight_js.visit_toplevel 
        ~tag_hook:(fun info categ -> 

          (* todo: use is_entity_def_category ? *)
          match categ with
          | HC.Function (HC.Def2 _) 
          | HC.Global (HC.Def2 _)
          | HC.Class (HC.Def2 _) 
          | HC.Method (HC.Def2 _) 
            ->
              Hashtbl.add hdefs_pos info true;
              let e = mk_entity ~root ~hcomplete_name_of_info 
                info categ 
              in
              Hashtbl.add hdefs e.Db.e_name e;
          | _ -> ()
        )
        prefs
        (ast, toks)
      ;
    );
  );

  (* step2: collecting uses *)
  files +> List.iter (fun file ->
    if verbose 
    then pr2 (spf "PHASE 2: %s" file);

    if file =~ ".*external/" 
    then pr2 (spf "skipping external file: %s" file)
    else begin

    let (ast2, _stat) = Parse_js.parse file in

    ast2 +> List.iter (fun (ast, (_str, toks)) ->

      let toks = toks +> Common.exclude (function
        | T.TCommentSpace _ -> true
        | _ -> false
      )
      in

      (* Only consider function or method calls. Otherwise names such 
       * as 'x', or 'yylex' which are variables or internal functions
       * are considered as having a huge count.
       * 
       *)
      let rec aux_toks toks = 
        match toks with
        (* The order of the rules are important here. We are 
         * being less and less precise in the pattern so the
         * precise pattern has to be first
         *)

        | T.T_IDENTIFIER ("JX", ii1)
          ::T.T_PERIOD(_)
          ::T.T_IDENTIFIER (s, ii_last)
          ::T.T_LPAREN(_)
          ::xs when Ast.col_of_info ii1 <> 0 ->

            Hashtbl.find_all hdefs s +> List.iter (fun entity ->
              (* todo: should check that method of appropriate class
               * but class analysis is complicated in Javascript.
               *)
              match entity.Db.e_kind with
              |  Db.Class _ ->
                entity.Db.e_number_external_users <-
                  entity.Db.e_number_external_users + 1;
              | _ -> ()
            );
            aux_toks xs

        | T.T_PERIOD _
          ::T.T_IDENTIFIER(s, ii)
          ::T.T_LPAREN(_)
          ::xs
          ->
            if not (is_common_method s)
            then
            Hashtbl.find_all hdefs s +> List.iter (fun entity ->
              (* todo: should check that method of appropriate class
               * but class analysis is complicated in Javascript
               * I compensate at least a little this problem by
               * calling adjust_method_external_users below.
               *)
              (match entity.Db.e_kind with
              | Db.Method _ ->
                entity.Db.e_number_external_users <-
                  entity.Db.e_number_external_users + 1;
              | _ -> ()
              )
            );
            aux_toks xs
        |
          T.T_IDENTIFIER(s, ii)
          ::T.T_LPAREN(_)
          ::xs
          ->
           (* could be the tokens for the def *)
           if not (Hashtbl.mem hdefs_pos ii) then begin

             Hashtbl.find_all hdefs s +> List.iter (fun entity ->
              (* todo: should check that method of appropriate class
               * but class analysis is complicated in Javascript
               *)
               if entity.Db.e_kind = Db.Function
               then
                 entity.Db.e_number_external_users <-
                   entity.Db.e_number_external_users + 1;
             );
           end;
           aux_toks xs

        | [] -> ()
        | x::xs ->
            aux_toks xs
      in
      aux_toks toks;
    )
    
    end
  );

  (* step3: adding cross reference information *)
  let entities_arr = 
    Common.hash_to_list hdefs +> List.map snd +> Array.of_list
  in
  Db.adjust_method_or_field_external_users ~verbose entities_arr;

  let dirs = dirs +> List.map (fun s -> 
    Common.filename_without_leading_path root s) in
  let dirs = Db.alldirs_and_parent_dirs_of_relative_dirs dirs in

  { Db.
    root = root;

    dirs = dirs +> List.map (fun d -> 
      d
      , 0); (* TODO *)
    files = files +> List.map (fun f -> 
      Common.filename_without_leading_path root f
      , 0); (* TODO *)

    entities = entities_arr;
  }
