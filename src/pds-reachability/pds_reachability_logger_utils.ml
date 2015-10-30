open Batteries;;

open Dot_file_logger_utils;;

include Pds_reachability_logger_utils_types;;

module Make(Basis : Pds_reachability_basis.Basis)
           (Dph : Pds_reachability_types_stack.Dynamic_pop_handler
              with type stack_element = Basis.stack_element
               and type state = Basis.state
           )
           (Types : Pds_reachability_types.Types
              with type stack_element = Basis.stack_element
               and type state = Basis.state
               and type targeted_dynamic_pop_action =
                          Dph.targeted_dynamic_pop_action
               and type untargeted_dynamic_pop_action =
                          Dph.untargeted_dynamic_pop_action
           )
           (Structure : Pds_reachability_structure.Structure
              with type stack_element = Basis.stack_element
               and type edge = Types.edge
               and type node = Types.node
               and type targeted_dynamic_pop_action =
                          Types.targeted_dynamic_pop_action
               and type untargeted_dynamic_pop_action =
                          Types.untargeted_dynamic_pop_action
           ) =
struct
  module Logger_basis =
  struct
    type level = pds_reachability_logger_level;;
    let compare_level = compare_pds_reachability_logger_level;;
    let pp_level = pp_pds_reachability_logger_level;;
    let default_level = Pds_reachability_log_nothing;;
    
    type name = pds_reachability_logger_name;;
    let string_of_name (Pds_reachability_logger_name(pfx,major,minor)) =
      pfx ^ "_PDR_" ^ string_of_int major ^ "_" ^ string_of_int minor
    ;;

    type dot_node_id = Types.node;;
    let string_of_dot_node_id node =
      match node with
      | Types.State_node state -> Basis.pp_state state
      | Types.Intermediate_node n -> "#" ^ string_of_int n
      | Types.Initial_node (state,element) ->
        Printf.sprintf "%s +(%s)"
          (Basis.pp_state state) (Basis.pp_stack_element element)
    ;;

    type data = Structure.structure;;
    let string_of_edge_action edge_action =
      match edge_action with
      | Pds_reachability_types_stack.Push element ->
        Printf.sprintf "push %s" (Basis.pp_stack_element element)
      | Pds_reachability_types_stack.Pop element ->
        Printf.sprintf "pop %s" (Basis.pp_stack_element element)
      | Pds_reachability_types_stack.Nop ->
        "nop"
      | Pds_reachability_types_stack.Pop_dynamic_targeted action ->
        Printf.sprintf "popdyn %s" (Dph.pp_targeted_dynamic_pop_action action)
    ;;
    let graph_of structure =
      let nodes = Structure.enumerate_nodes structure in
      let edges = Structure.enumerate_edges structure in
      let nodes' =
        nodes
        |> Enum.map
          (fun node ->
            { dot_node_id = node
            ; dot_node_color =
              (match node with
              | Types.State_node _ | Types.Intermediate_node _ -> None
              | Types.Initial_node _ -> Some "yellow")
            ; dot_node_text =
              Some (string_of_dot_node_id node)
            }
          )
      in
      let edges' =
        edges
        |> Enum.map
          (fun edge ->
            { dot_edge_source = edge.Types.source
            ; dot_edge_target = edge.Types.target
            ; dot_edge_text =
              Some (string_of_edge_action edge.Types.edge_action)
            }
          )
      in
      (nodes',edges')
    ;;
  end;;

  module Logger = Dot_file_logger_utils.Make(Logger_basis);;

  include Logger;;
end;;
