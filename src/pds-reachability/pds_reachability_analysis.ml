(**
   This module defines the actual PDS reachability analysis.
*)

open Batteries;;

open Pds_reachability_types_stack;;
open Pp_utils;;

let lazy_logger = Logger_utils.make_lazy_logger "Pds_reachability_analysis";;

module type Analysis =
sig
  include Pds_reachability_types.Types;;

  (** The type of edge-generating functions used in this analysis. *)
  type edge_function = state -> (stack_action list * state) Enum.t

  (** The type of functions to generate untargeted dynamic pop actions in this
      analysis. *)
  type untargeted_dynamic_pop_action_function =
    state -> untargeted_dynamic_pop_action Enum.t

  exception Reachability_request_for_non_start_state of state;;

  (** The type of a reachability analysis in this module. *)
  type analysis

  (** The empty analysis.  This analysis has no states, edges, or edge
      functions. *)
  val empty : analysis

  (** Adds a single edge to a reachability analysis. *)
  val add_edge
    : state -> stack_action list -> state -> analysis -> analysis

  (** Adds a function to generate edges for a reachability analysis.  Given a
      source node, the function generates edges from that source node.  The
      function must be pure; for a given source node, it must generate all edges
      that it can generate on the first call. *)
  val add_edge_function : edge_function -> analysis -> analysis

  (** Adds an untargeted pop action to a reachability analysis.  Untargeted pop
      action are similar to targeted pop actions except that they are not
      created as an edge with a target node; instead, the target is decided in
      some way by the pushed element that the untargeted dynamic pop is
      consuming. *)
  val add_untargeted_dynamic_pop_action
    : state -> untargeted_dynamic_pop_action -> analysis -> analysis

  (** Adds a function to generate untargeted dynamic pop ations for a
      reachability analysis.  Given a source node, the function generates
      untargeted actions from that source node.  The function must be pure; for
      a given source, it must generate all actions that it can generate on the
      first call. *)
  val add_untargeted_dynamic_pop_action_function
    : untargeted_dynamic_pop_action_function -> analysis -> analysis

  (** Adds a state and initial stack element to the analysis.  This permits the
      state to be used as the source state of a call to [get_reachable_states].
  *)
  val add_start_state
    : state
    -> stack_action list
    -> analysis
    -> analysis

  (** Determines whether the reachability analysis is closed. *)
  val is_closed : analysis -> bool

  (** Takes a step toward closing a given reachability analysis.  If the
      analysis is already closed, it is returned unchanged. *)
  val closure_step : analysis -> analysis

  (** Fully closes the provided analysis. *)
  val fully_close : analysis -> analysis

  (** Determines the states which are reachable from a given state and initial
      stack element.  This state must have been added to the analysis
      previously.  If the analysis is not fully closed, then the enumeration of
      reachable states may be incomplete.  *)
  val get_reachable_states
    : state
    -> stack_action list
    -> analysis
    -> state Enum.t

  (** Pretty-printing function for the analysis. *)
  val pp_analysis : analysis pretty_printer
  val show_analysis : analysis -> string

  (** An exception raised when a reachable state query occurs before the state
      is added as a start state. *)
  exception Reachability_request_for_non_start_state of state;;

  (** Determines the size of the provided analysis in terms of both node and
      edge count (respectively). *)
  val get_size : analysis -> int * int
end;;

module Make
    (Basis : Pds_reachability_basis.Basis)
    (Dph : Pds_reachability_types_stack.Dynamic_pop_handler
     with type stack_element = Basis.stack_element
      and type state = Basis.state)
    (Work_collection_template_impl :
       Pds_reachability_work_collection.Work_collection_template)
  : Analysis
    with type state = Basis.state
     and type stack_element = Basis.stack_element
     and type targeted_dynamic_pop_action = Dph.targeted_dynamic_pop_action
     and type untargeted_dynamic_pop_action = Dph.untargeted_dynamic_pop_action
=
struct
  (********** Create and wire in appropriate components. **********)

  module Types = Pds_reachability_types.Make(Basis)(Dph);;
  module Work = Pds_reachability_work.Make(Basis)(Types);;
  module Work_collection_impl = Work_collection_template_impl(Work);;
  module Structure = Pds_reachability_structure.Make(Basis)(Dph)(Types);;

  include Types;;

  type edge_function = state -> (stack_action list * state) Enum.t;;
  type untargeted_dynamic_pop_action_function =
    state -> untargeted_dynamic_pop_action Enum.t;;

  (********** Define utility data structures. **********)

  exception Reachability_request_for_non_start_state of state;;

  module State_set = Set.Make(Basis.State_ord);;

  module Node_ord =
  struct
    type t = Types.node
    let compare = Types.compare_node
  end;;

  module Node_set = Set.Make(Node_ord);;
  module Node_map = Map.Make(Node_ord);;

  (********** Define analysis structure. **********)

  type node_awareness =
    | Seen
    (* Indicates that this node exists somewhere in the work queue but not in
       the analysis structure. *)
    | Expanded
    (* Indicates that this node exists somewhere in the analysis structure and
       has already been expanded.  An expanded node responds to edge functions,
       for instance. *)
    [@@deriving show]
  let _ = show_node_awareness;; (* To ignore an unused generated function. *)

  type analysis =
    { node_awareness_map : node_awareness Node_map.t
          [@printer Pp_utils.pp_map pp_node pp_node_awareness Node_map.enum]
    (* A mapping from each node to whether the analysis is aware of it.  Any node
       not in this map has not been seen in any fashion.  Every node that has been
       seen will be mapped to an appropriate [node_awareness] value. *)
    ; known_states : State_set.t
          [@printer Pp_utils.pp_set Basis.pp_state State_set.enum]
    (* A collection of all states appearing somewhere within the reachability
       structure (whether they have been expanded or not). *)
    ; reachability : Structure.structure
    (* The underlying structure maintaining the nodes and edges in the graph. *)
    ; edge_functions : edge_function list
          [@printer fun formatter functions ->
                 Format.fprintf formatter "(length = %d)"
                   (List.length functions)]
    (* The list of all edge functions for this analysis. *)
    ; untargeted_dynamic_pop_action_functions :
        untargeted_dynamic_pop_action_function list
          [@printer fun formatter functions ->
                 Format.fprintf formatter "(length = %d)"
                   (List.length functions)]
    (* The list of all untargeted dynamic pop action functions. *)
    ; work_collection : Work_collection_impl.work_collection
    (* The collection of work which has not yet been performed. *)
    }
    [@@deriving show]
  ;;

  (********** Analysis utility functions. **********)

  let add_work work analysis =
    match work with
    | Work.Expand_node node ->
      if Node_map.mem node analysis.node_awareness_map
      then analysis
      else
        { analysis with
          work_collection =
            Work_collection_impl.offer work analysis.work_collection
        ; node_awareness_map =
            Node_map.add node Seen analysis.node_awareness_map
        }
    | Work.Introduce_edge edge ->
      (* TODO: We might want to filter duplicate introduce-edge steps from the
         work collection. *)
      if Structure.has_edge edge analysis.reachability
      then analysis
      else
        { analysis with
          work_collection =
            Work_collection_impl.offer work analysis.work_collection
        }
    | Work.Introduce_untargeted_dynamic_pop(from_node,action) ->
      (* TODO: We might want to filter duplicate introduce-udynpop steps from
         the work collection. *)
      if Structure.has_untargeted_dynamic_pop_action
          from_node action analysis.reachability
      then analysis
      else
        { analysis with
          work_collection =
            Work_collection_impl.offer work analysis.work_collection
        }
  ;;

  let add_works works analysis = Enum.fold (flip add_work) analysis works;;

  let next_edge_in_sequence from_node actions to_node =
    let next_node,action =
      match actions with
      | [] -> to_node,Nop
      | [x] -> to_node,x
      | x::xs -> Intermediate_node(to_node,xs),x
    in
    {source=from_node;target=next_node;edge_action=action}
  ;;

  (********** Define analysis operations. **********)

  let get_size analysis =
    let reachability = analysis.reachability in
    let node_count = Enum.count @@ Structure.enumerate_nodes reachability in
    let edge_count = Enum.count @@ Structure.enumerate_edges reachability in
    (node_count, edge_count)
  ;;

  let empty =
    { node_awareness_map = Node_map.empty
    ; known_states = State_set.empty
    ; reachability = Structure.empty
    ; edge_functions = []
    ; untargeted_dynamic_pop_action_functions = []
    ; work_collection = Work_collection_impl.empty
    };;

  let add_edge from_state stack_action_list to_state analysis =
    let edge =
      next_edge_in_sequence
        (State_node from_state)
        stack_action_list
        (State_node to_state)
    in
    analysis |> add_work (Work.Introduce_edge edge)
  ;;

  let add_edge_function edge_function analysis =
    (* First, we have to catch up on this edge function by calling it with every
       state present in the analysis. *)
    let work =
      analysis.known_states
      |> State_set.enum
      |> Enum.map
        (fun from_state ->
           from_state
           |> edge_function
           |> Enum.map
             (fun (actions,to_state) ->
                let edge =
                  next_edge_in_sequence
                    (State_node from_state)
                    actions
                    (State_node to_state)
                in
                (* We know that the from_node has already been introduced. *)
                Work.Introduce_edge edge
             )
        )
      |> Enum.concat
    in
    (* Now we add both the catch-up work (so the analysis is as if the edge
       function was present all along) and the edge function (so it'll stay
       in sync in the future). *)
    { (add_works work analysis) with
      edge_functions = edge_function :: analysis.edge_functions
    }
  ;;

  let add_untargeted_dynamic_pop_action from_state pop_action analysis =
    let from_node = State_node from_state in
    analysis
    |> add_work (Work.Introduce_untargeted_dynamic_pop(from_node, pop_action))
  ;;

  let add_untargeted_dynamic_pop_action_function pop_action_fn analysis =
    (* First, we have to catch up on this function by calling it with every
       state we know about. *)
    let work =
      analysis.known_states
      |> State_set.enum
      |> Enum.map
        (fun from_state ->
           from_state
           |> pop_action_fn
           |> Enum.map
             (fun action ->
                let from_node = State_node from_state in
                Work.Introduce_untargeted_dynamic_pop(from_node, action)
             )
        )
      |> Enum.concat
    in
    (* Now we add both the catch-up work (so the analysis is as if the function
       was present all along) and the function (so it'll stay in sync in the
       future). *)
    { (add_works work analysis) with
      untargeted_dynamic_pop_action_functions =
        pop_action_fn :: analysis.untargeted_dynamic_pop_action_functions
    }
  ;;

  let add_start_state state stack_actions analysis =
    analysis
    |> add_work
      (Work.Expand_node(Intermediate_node(State_node(state), stack_actions)))
  ;;

  let is_closed analysis =
    Work_collection_impl.is_empty analysis.work_collection
  ;;

  let closure_step analysis =
    let (new_work_collection, work_opt) =
      Work_collection_impl.take analysis.work_collection
    in
    match work_opt with
    | None -> analysis
    | Some work ->
      let analysis = { analysis with work_collection = new_work_collection } in
      (* A utility function to add a node to a set *only if* it needs to be
         expanded. *)
      let expand_add node nodes_to_expand =
        let entry =
          Node_map.Exceptionless.find node analysis.node_awareness_map
        in
        if entry <> Some Expanded
        then Node_set.add node nodes_to_expand
        else nodes_to_expand
      in
      match work with
      | Work.Expand_node node ->
        begin
          (* We're adding to the analysis a node that it does not contain. *)
          match node with
          | State_node(state) ->
            (* We just need to introduce this node to all of the edge functions
               that we have accumulated so far. *)
            let work =
              analysis.edge_functions
              |> List.enum
              |> Enum.map (fun f -> f state)
              |> Enum.concat
              |> Enum.map (fun (actions,to_state) ->
                  let edge =
                    next_edge_in_sequence
                      (State_node state)
                      actions
                      (State_node to_state)
                  in
                  (* We know that the from_node has already been introduced. *)
                  Work.Introduce_edge edge
                )
            in
            { (add_works work analysis) with
              known_states = analysis.known_states |> State_set.add state
            ; node_awareness_map =
                analysis.node_awareness_map
                |> Node_map.add node Expanded
            }
          | Intermediate_node(target, actions) ->
            (* The only edge implied by an intermediate node is the one that
               moves along the action chain. *)
            let work =
              begin
                match actions with
                | [] ->
                  Work.Introduce_edge(
                    {source=node;target=target;edge_action=Nop})
                | [action] ->
                  Work.Introduce_edge(
                    {source=node;target=target;edge_action=action})
                | action::actions' ->
                  Work.Introduce_edge(
                    { source=node
                    ; target=Intermediate_node(target, actions')
                    ; edge_action=action})
              end
            in
            (* We now have some work based upon the node to introduce.  We must
               also mark the node as present. *)
            { (add_work work analysis) with
              node_awareness_map =
                Node_map.add node Expanded analysis.node_awareness_map
            }
        end
      | Work.Introduce_edge edge ->
        let { source = from_node
            ; target = to_node
            ; edge_action = action
            } = edge
        in
        let analysis' =
          (* When an edge is introduced, all of the edges connecting to it should
             be closed with it.  These new edges are introduced to the work queue
             and drive the gradual expansion of closure.  It may also be necessary
             to expand some nodes which have not yet been expanded. *)
          let edge_work, nodes_to_expand =
            match action with
            | Nop ->
              (* The only closure for nop edges is to find all pushes that lead
                 into them and route them through the nop.  As this creates new
                 push edges, the target should be expanded when at least one
                 edge is created. *)
              let work =
                analysis.reachability
                |> Structure.find_push_edges_by_target from_node
                |> Enum.map
                  (fun (from_node', element) ->
                     Work.Introduce_edge(
                       { source = from_node'
                       ; target = to_node
                       ; edge_action = Push element
                       })
                  )
              in
              if Enum.is_empty work
              then (work, Node_set.empty)
              else (work, expand_add to_node Node_set.empty)
            | Push k ->
              (* Any nop, pop, or popdyn edges at the target of this push can be
                 closed.  Any new targets are candidates for expansion. *)
              let nop_work_list, nop_expand_set =
                analysis.reachability
                |> Structure.find_nop_edges_by_source to_node
                |> Enum.fold
                  (fun (work_list, expand_set) to_node' ->
                     let work =
                       Work.Introduce_edge(
                         { source = from_node
                         ; target = to_node'
                         ; edge_action = Push k
                         })
                     in
                     (work::work_list, expand_add to_node' expand_set)
                  )
                  ([], Node_set.empty)
              in
              let pop_work_list, pop_expand_set =
                analysis.reachability
                |> Structure.find_pop_edges_by_source to_node
                |> Enum.filter
                  (fun (_, element) -> equal_stack_element k element)
                |> Enum.fold
                  (fun (work_list, expand_set) (to_node', _) ->
                     let work =
                       Work.Introduce_edge(
                         { source = from_node
                         ; target = to_node'
                         ; edge_action = Nop
                         })
                     in
                     (work::work_list, expand_add to_node' expand_set)
                  )
                  ([], Node_set.empty)
              in
              let popdyn_work_list, popdyn_expand_set =
                analysis.reachability
                |> Structure.find_targeted_dynamic_pop_edges_by_source to_node
                |> Enum.fold
                  (fun (work_list, expand_set) (to_node', action) ->
                     Dph.perform_targeted_dynamic_pop k action
                     |> Enum.fold
                       (fun (work_list, expand_set) stack_actions ->
                          let edge =
                            next_edge_in_sequence
                              from_node stack_actions to_node'
                          in
                          let work = Work.Introduce_edge edge in
                          (work::work_list, expand_add to_node' expand_set)
                       ) (work_list,expand_set)
                  ) ([],Node_set.empty)
              in
              ( Enum.concat @@ List.enum
                  [ List.enum nop_work_list
                  ; List.enum pop_work_list
                  ; List.enum popdyn_work_list
                  ]
              , Node_set.union popdyn_expand_set @@
                Node_set.union nop_expand_set pop_expand_set
              )
            | Pop k ->
              (* Pop edges can only close with the push edges that precede them.
                 The target of these new edges is a candidate for expansion. *)
              let work =
                analysis.reachability
                |> Structure.find_push_edges_by_target from_node
                |> Enum.filter_map
                  (fun (from_node', element) ->
                     if equal_stack_element element k
                     then Some(
                         Work.Introduce_edge(
                           { source = from_node'
                           ; target = to_node
                           ; edge_action = Nop
                           }))
                     else None
                  )
              in
              if Enum.is_empty work
              then (work, Node_set.empty)
              else (work, expand_add to_node Node_set.empty)
            | Pop_dynamic_targeted action ->
              (* Dynamic pop edges can only close with push edges that precede
                 them.  The target of these new edges is a candidate for
                 expansion. *)
              let (work_list, to_expand) =
                analysis.reachability
                |> Structure.find_push_edges_by_target from_node
                |> Enum.fold
                  (fun (work_list, expand_set) (from_node', element) ->
                     Dph.perform_targeted_dynamic_pop element action
                     |> Enum.fold
                       (fun (work_list, expand_set) stack_actions ->
                          let edge =
                            next_edge_in_sequence
                              from_node' stack_actions to_node
                          in
                          let work = Work.Introduce_edge edge in
                          (work::work_list, expand_add to_node expand_set)
                       ) (work_list,expand_set)
                  ) ([],Node_set.empty)
              in (List.enum work_list, to_expand)
          in
          let expand_work = nodes_to_expand
                            |> Node_set.enum
                            |> Enum.map (fun node -> Work.Expand_node node)
          in
          add_works (Enum.append edge_work expand_work) analysis
        in
        { analysis' with
          reachability = analysis'.reachability |> Structure.add_edge edge
        }
      | Work.Introduce_untargeted_dynamic_pop(from_node,action) ->
        (* Untargeted dynamic pops can only close with the push edges that
           reach them.  Any targets of the resulting edges are candidates for
           expansion. *)
        let analysis' =
          let (work_list, nodes_to_expand) =
            analysis.reachability
            |> Structure.find_push_edges_by_target from_node
            |> Enum.fold
              (fun (work_list, expand_set) (from_node', element) ->
                 Dph.perform_untargeted_dynamic_pop element action
                 |> Enum.fold
                   (fun (work_list, expand_set) (stack_action_list, to_state) ->
                      let to_node = State_node(to_state) in
                      let edge =
                        next_edge_in_sequence
                          from_node' stack_action_list to_node
                      in
                      let work = Work.Introduce_edge edge in
                      (work::work_list, expand_add to_node expand_set)
                   ) (work_list, expand_set)
              ) ([],Node_set.empty)
          in
          let expand_work = nodes_to_expand
                            |> Node_set.enum
                            |> Enum.map (fun node -> Work.Expand_node node)
          in
          add_works (Enum.append (List.enum work_list) expand_work) analysis
        in
        { analysis' with
          reachability = analysis'.reachability
                         |> Structure.add_untargeted_dynamic_pop_action
                           from_node action
        }
  ;;

  let rec fully_close analysis =
    if is_closed analysis
    then analysis
    else fully_close @@ closure_step analysis
  ;;

  let get_reachable_states state stack_actions analysis =
    let node = Intermediate_node(State_node(state), stack_actions) in
    if Node_map.mem node analysis.node_awareness_map
    then
      (*
        If a state is reachable by empty stack from the given starting state,
        then there will be a nop edge to it.  It's that simple once closure
        is finished.
      *)
      analysis.reachability
      |> Structure.find_nop_edges_by_source node
      |> Enum.filter_map
        (fun node ->
           match node with
           | State_node state -> Some state
           | Intermediate_node _ -> None
        )
    else
      raise @@ Reachability_request_for_non_start_state state
  ;;
end;;
