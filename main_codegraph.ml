(*
 * Please imagine a long and boring gnu-style copyright notice 
 * appearing just here.
 *)
open Common

module Model = Model3
module View = View3

(*****************************************************************************)
(* Purpose *)
(*****************************************************************************)
(* 
 * Main entry point of codegraph, a package/module/type/function/...
 * hierarchical dependency visualizer using mainly a Dependency
 * Structure Matrix (DSM).
 * A node-link display of hierarchical graphs (or hypergraphs) would be nice
 * too, but it is far more complex to draw than matrices and does
 * not scale as well visually apparently.
 * See http://en.wikipedia.org/wiki/Design_structure_matrix
 * 
 * It seems there are a few commercial projects using DSM (Ndepend,
 * Structure101), so this looks like a viable direction to pursue to
 * visualize a software architecture.
 * 
 * requirements:
 *  - different granularities for x-to-x relationships
 *    (packages to packages, modules to packages, functions, constructors, etc),
 *    so one can get:
 *    * package (or directory) projection to reduce the size of the graph and
 *      get a high-level view of the architecture ("package mode")
 *    * with or without external/ dependencies
 *    * possibiltiy to get a slice of the graph for just a directory
 *      with a package (or directory) projection for external dependencies
 *      ("module mode")
 *    * possiblity to zoom to see the actual functions of a package involved
 *      in a dependency. This is especially useful for edges where
 *      we don't understand why there exists a dependency.
 *  - variable arrow size (but the count number in the matrix does that too)
 *  - variable node size (but the count number in same row does that too)
 * 
 * This tool also contains some actions to generate data for different
 * graph visualizer, e.g. Gephi, Guess. todo? backend for Graphviz? Phylomel?
 * old: $ pm_depend [-lang X] [-with-extern] [-depth n] -o filename /path/dir
 * 
 * related work: 
 * - lattix.com, the startup where the original paper on DSM
 *   at OOPSLA'05 comes from.
 * - ndepend.com, 
 *   http://www.ndepend.com/Doc_VS_Arch.aspx
 *   http://codebetter.com/patricksmacchia/2009/08/24/identify-code-structure-patterns-at-a-glance/
 * - structure101
 *   http://www.headwaysoftware.com/products/index.php#page-top
 * 
 * - http://depfind.sourceforge.net/, a dependency extraction tool for
 *   Java
 * 
 * - http://mcis.polymtl.ca/~bram/makao/index.html also use GUESS
 *   and Prolog :)
 * - http://infotectonica.com/juliet/tour/, seems more oriented on
 *   query, anserwing questions like who uses this field.
 * 
 * - google search images: dependency+graph+visualization, get many
 *   links from there 
 * 
 * 
 * history:
 *  - quick look at work on software architecture because of Banatre
 *    while a master student at IRISA, and later Schmidt, while a PhD,
 *    looking at work of Shaw and Garlan and the different
 *    architecture patterns (whiteboard, pipe, layers, etc).
 *  - started to draw hypergraphs of architecture while supervising a
 *    student project at EMN (submarine game), and advocated they were
 *    better than UML diagrams (I think after reading Harel's papers on
 *    history of statecharts in HOPL-III)
 *  - dir to dir dependencies during coccinelle project? 
 *    Projections were hardcoded each time for each use. 
 *    No generic framework (like the hierarchical dependency matrix).
 *    Done for C (then for PHP later, and then for OCaml far later).
 *  - very nice picture of architecture of Linux kernel sent by Gilles,
 *    the "map of the Linux kernel"
 *  - found that having a graph of module dependencies was very useful
 *    when refactored the c-- and mmm codebase, thx to ocamldot.
 *    But felt the need to have variable-size arrows (and nodes) and also
 *    the ability to get more information when clicking on an edge, 
 *    to actually see what are the functions involved in a dependency
 *    for instance.
 *  - flibotonomy by Greg Scheschte for PHP, but focused on the nodes
 *    instead of the edges (which I think are more important).
 *  - overlay, and cmf -y to display dependencies at "package" level
 *  - pm_depend, ocaml dependencies backend, ~package_depth, ~with_extern.
 *    In some ways it extracts the dependency information I have 
 *    in my Makefiles where I care about the order of the directories
 *    and files. The ~package_depth and ~with_extern parameters are just
 *    special cases of the general idea of displaying at different
 *    granularity dependencies depending on the directory.
 *    Finally it was limited to just package/module (pm_depend) but quickly
 *    you want to know the actual functions/classes that are involved in
 *    a dependency.
 *  - gephi/guess visualization, but even with -no_extern, it does not
 *    scale very well for www. It's ok for pfff, but even for 
 *    the full source of pfff the graph is quite noisy.
 *  - discover DSM of ndepend.com while doing a google search images on
 *    "dependency+graph+visualization"
 * 
 *  - gradually realize the importance of layered structures,
 *    which are actually enforced in OCaml by the linker.
 *  - gradually realize the importance of dependencies and how
 *    they are at the essence of software architecture. Code is
 *    a tree when looked locally (AST), but it's really a graph
 *    of dependencies when looked globally.
 * 
 * todo: 
 *  - can codegraph does a good job to convey the software architecture
 *    of codegraph itself? does it show clearly that Graph_code.graph and
 *    dependencies_matrix_code.dm are the essential data structures? And
 *    can it show the important fields?
 *  - maybe edge-bundles could make the node-link display approach
 *    scale better.
 *  - generate a node-link graph for the current matrix configuration; use
 *    graphviz as a first step.
 * 
 * (comments that were in graph_modules_packages_ml.ml)
 * alternatives:
 *  - ocamldoc -dot ...
 *    But if there is one parse error or a module not found, then 
 *    ocamldoc fails. Also there is no package "projection" so it's 
 *    hard to apply on large projects. There is also no with-extern view
 *    with the slice of the graph to a directory.
 *    TODO it can potentially support more code though, by using camlp4.
 *  - ocamldoc with graphviz  
 *    graphviz does not do variable node size for free as in gephi
 *  - ocamldoc -dot-reduce ... 
 *    The -dot-reduce is good for layering, but sometimes
 *    it's also good to see things without the reduction (especially
 *    with gephi). See for instance the graph for tiger with ocamldoc
 *    vs pm_depend. I can see all the real callers to option.ml.
 *    TODO the reduce and layering is also useful
 *  - ocamldoc -dot-colors
 *    TODO this is useful.
 *    It's somehow covered by the strongly-connected + coloring in gephi.
 *  - graphviz backend? graphviz is good for layers, but
 *    you lose space because the high-level stuff is at the top but alone.
 *    With gephi/fatlas, by putting high-level stuff at the center, 
 *    you lose less space? Also graphviz does not scale very well.
 * 
 *)

(*****************************************************************************)
(* Flags *)
(*****************************************************************************)

let verbose = ref false

(* old *)
let with_extern = ref false
let package_depth = ref 0

let lang = ref "ml"
(* todo? gephi mode? that set default output file to something different? *)
let output_file = ref "/tmp/pm.gdf"

(* action mode *)
let action = ref ""

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(*****************************************************************************)
(* Model Helpers *)
(*****************************************************************************)

let build_model root =
  let file = Filename.concat root "dependencies.marshall" in
  let g = Graph_code.load file in
  { Model.g = g; root = root; }

(*****************************************************************************)
(* Main action *)
(*****************************************************************************)

(* Find root of project with a dependencies.marshall file
 * and display slice of the dependency hieararchical matrix 
 * using arguments in xs.
 * todo? use -with_extern ?
 * 
 * todo: How load graph? Build on demand? easier to test things that way ... 
 * maybe can just cache and look if need to recompute the code graph?
 *)
let main_action xs =
  Logger.log Config.logger "codegraph" None;

  let root = Common.common_prefix_of_files_or_dirs xs in
  pr2 (spf "Using root = %s" root);
  
  let model = build_model root in
  (* todo: take command line argument to propose a specific slice of the graph*)
  let config = [] in

  let w = Model.init_world config model in
  View.mk_gui w

(*****************************************************************************)
(* Extra Actions *)
(*****************************************************************************)

(* ---------------------------------------------------------------------- *)
(* ML *)
(* ---------------------------------------------------------------------- *)
let rec dependencies_of_files_or_dirs lang xs =
  let verbose = !verbose in
  match lang, xs with
  | "ml", [dir] ->
      Graph_modules_packages_ml.dependencies
        ~verbose
        ~with_extern:!with_extern
        ~package_depth:!package_depth
        dir
  | _ -> failwith ("language not supported: " ^ lang)

let test_gdf xs =
  let _g = dependencies_of_files_or_dirs !lang xs in
  pr2 (spf "Writing data in %s" !output_file);
  raise Todo
  (*
  g +> Graph_guess.to_gdf        ~str_of_node:(fun s -> s) ~output:!output_file
  g +> Graph_gephi.graph_to_gefx ~str_of_node:(fun s -> s) ~output:!output_file
      ~tree:None~weight_edges:None
  *)

(* ---------------------------------------------------------------------- *)
(* Phylomel *)
(* ---------------------------------------------------------------------- *)

open Vec2
open BarnesHut

let update_state n fs bs fig =
  let delta = 0.05 in

  (* Update forces *)
  ForceDirectedLayout.do_calc_forces fs bs fig;
	
  (* Euler integration on each body *)
  for i=0 to n - 1 do
    let b = bs.(i) in
    let f = fs.(i) in
    b.p.x <-
      b.p.x +. delta *. b.v.x +. 1./.2. *. delta *. delta *. f.x;
    b.p.y <-
      b.p.y +. delta *. b.v.y +. 1./.2. *. delta *. delta *. f.y;
    b.v.x <- b.v.x +. delta *. f.x;
    b.v.y <- b.v.y +. delta *. f.y;
    f.x <- 0.;
    f.y <- 0.
  done

let test_phylomel geno_file =

  let svg_file = "/tmp/foo.svg" in
  (* We create four things :
   *  - genotypes collection
   * - distance matrix
   * - minimum spanning tree
   * - figure (graphical tree) 
   *)
  let collec = 
    Genotypes.read_file geno_file +> Genotypes.remove_duplicates
  in
  let dmat = GenoMat.create collec in
  let tree = Tree.prim_complete collec dmat in
(*
  let dist_mat = 
    [|
      [||];
      [|1|];
      [|1;2|];
    |]
  in
  let adj_mat = 
    [|
      [||];
      [|true|];
      [|true;false|];
    |]
  in

  let tree = Tree.create adj_mat dist_mat in
  let infos = [|"n0"; "n1"; "n2"|] in
*)

  let fig = Phylogram.radial_layout ~reframe:false 800. tree in
  
  (* Creates force array, bodies *)
  let n = Phylogram.size fig in
  let fs = Array.init n (fun _ -> Vec2.null ()) in
  let bs = Array.map ForceDirectedLayout.body_of_pos fig.Phylogram.ps in

  for i=0 to 2000 do
    update_state n fs bs fig
  done;

  let x0, y0 = (10.,10.) in
  Phylogram.unsafe_reframe (10.,10.) fig.Phylogram.ps;
  Phylogram.unsafe_crop_width (800.-.2.*.x0) fig.Phylogram.ps;
  fig.Phylogram.h <- Phylogram.height fig.Phylogram.ps +. 2. *. y0;  
    
  (* let x0 = 10. in *)
  (* unsafe_reframe (10., 10.) fig.ps; *)
  (* unsafe_crop_width (800.-.2.*.x0) fig.ps; *)

  let nodeinfo =
    (fun i -> Genotype.description collec.Genotypes.genos.(i))
    (* (fun i -> infos.(i)) *)
  in
  
  Phylogram.write_svg_file nodeinfo fig svg_file;
  ()

(* ---------------------------------------------------------------------- *)
let extra_actions () = [
  "-test_gdf", " <dirs>",
  Common.mk_action_n_arg test_gdf;
  "-test_phylomel", " <geno file>",
  Common.mk_action_1_arg test_phylomel;
]

(*****************************************************************************)
(* The options *)
(*****************************************************************************)

let all_actions () = 
  extra_actions () ++
  []

let options () = [
  "-lang", Arg.Set_string lang, 
  (spf " <str> choose language (default = %s)" !lang);
  "-o", Arg.Set_string output_file, 
  (spf " <file> default = %s" !output_file);

  "-with_extern", Arg.Set with_extern,
  " includes external references";
  "-package_mode", Arg.Set_int package_depth,
  " <n> project at depth n";
  
  "-verbose", Arg.Set verbose, 
  " ";
  ] ++
  Common.options_of_actions action (all_actions()) ++
  Common.cmdline_flags_devel () ++
  [
    "-version",   Arg.Unit (fun () -> 
      pr2 (spf "CodeGraph version: %s" Config.version);
      exit 0;
    ), 
    "  guess what";
  ]

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let main () = 
  (* Common_extra.set_link(); *)
  let usage_msg = 
    spf "Usage: %s [options] <file or dir> \nDoc: %s\nOptions:"
      (Common.basename Sys.argv.(0))
      "https://github.com/facebook/pfff/wiki/Codegraph"
  in
  (* does side effect on many global flags *)
  let args = Common.parse_options (options()) usage_msg Sys.argv in

  (* must be done after Arg.parse, because Common.profile is set by it *)
  Common.profile_code "Main total" (fun () -> 
    (match args with
    (* --------------------------------------------------------- *)
    (* actions, useful to debug subpart *)
    (* --------------------------------------------------------- *)
    | xs when List.mem !action (Common.action_list (all_actions())) -> 
        Common.do_action !action xs (all_actions())

    | _ when not (Common.null_string !action) -> 
        failwith ("unrecognized action or wrong params: " ^ !action)

    (* --------------------------------------------------------- *)
    (* main entry *)
    (* --------------------------------------------------------- *)
    | x::xs -> 
        main_action (x::xs)

    (* --------------------------------------------------------- *)
    (* empty entry *)
    (* --------------------------------------------------------- *)
    | [] -> 
        Common.usage usage_msg (options()); 
        failwith "too few arguments"
    )
  )

(*****************************************************************************)
let _ =
  Common.main_boilerplate (fun () -> 
    main ();
  )
