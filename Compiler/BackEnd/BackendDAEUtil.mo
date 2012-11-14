/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */
  
encapsulated package BackendDAEUtil
" file:        BackendDAEUtil.mo
  package:     BackendDAEUtil 
  description: BackendDAEUtil comprised functions for BackendDAE data types.

  RCS: $Id$

  This module is a lowered form of a DAE including equations
  and simple equations in
  two separate lists. The variables are split into known variables
  parameters and constants, and unknown variables,
  states and algebraic variables.
  The module includes the BLT sorting algorithm which sorts the
  equations into blocks, and the index reduction algorithm using
  dummy derivatives for solving higher index problems.
  It also includes the tarjan algorithm to detect strong components
  in the BLT sorting."

public import BackendDAE;
public import DAE;
public import Env;

protected import Absyn;
protected import Algorithm;
protected import BackendDump;
protected import BackendDAECreate;
protected import BackendDAEOptimize;
protected import BackendDAETransform;
protected import BackendEquation;
protected import BackendVariable;
protected import BackendVarTransform;
protected import BaseHashTable;
protected import BinaryTree;
protected import CheckModel;
protected import ComponentReference;
protected import Ceval;
protected import ClassInf;
protected import Config;
protected import DAEUtil;
protected import DAEDump;
protected import Derive;
protected import Debug;
protected import Error;
protected import Expression;
protected import ExpressionSimplify;
protected import ExpressionDump;
protected import Flags;
protected import Global;
protected import IndexReduction;
protected import Inline;
protected import List;
protected import Matching;
protected import OnRelaxation;
protected import SCode;
protected import System;
protected import Types;
protected import Util;
protected import Values;

public 
type Var = BackendDAE.Var;
type VarKind = BackendDAE.VarKind;
type VariableArray = BackendDAE.VariableArray;
type EquationArray = BackendDAE.EquationArray;
type ExternalObjectClasses = BackendDAE.ExternalObjectClasses;
type BackendDAEType = BackendDAE.BackendDAEType;
type SymbolicJacobians = BackendDAE.SymbolicJacobians;
type MatchingOptions = BackendDAE.MatchingOptions;
type EqSystems = BackendDAE.EqSystems;
type WhenClause = BackendDAE.WhenClause;
type ZeroCrossing = BackendDAE.ZeroCrossing; 
                


/*************************************************
 * checkBackendDAE and stuff 
 ************************************************/

public function checkBackendDAEWithErrorMsg"function: checkBackendDAEWithErrorMsg
  author: Frenkel TUD
  run checkDEALow and prints all errors"
  input BackendDAE.BackendDAE inBackendDAE;
protected
  list<tuple<DAE.Exp,list<DAE.ComponentRef>>> expCrefs;
  list<BackendDAE.Equation> wrongEqns;
algorithm  
  _ := matchcontinue (inBackendDAE)
    local
      Integer i1,i2;
      Boolean samesize;
    case (_)
      equation
        false = Flags.isSet(Flags.CHECK_BACKEND_DAE);
      then
        ();
    case (BackendDAE.DAE(eqs = BackendDAE.EQSYSTEM(orderedVars = BackendDAE.VARIABLES(numberOfVars = i1),orderedEqs = BackendDAE.EQUATION_ARRAY(size = i2))::{}))
      equation
        //true = Flags.isSet(Flags.CHECK_BACKEND_DAE);
        //Check for correct size
        samesize = i1 == i2;
        Debug.fcall(Flags.CHECK_BACKEND_DAE,print,"No. of Equations: " +& intString(i1) +& " No. of BackendDAE.Variables: " +& intString(i2) +& " Samesize: " +& boolString(samesize) +& "\n");
        (expCrefs,wrongEqns) = checkBackendDAE(inBackendDAE);
        printcheckBackendDAEWithErrorMsg(expCrefs,wrongEqns);
      then
        ();
     end matchcontinue;
end checkBackendDAEWithErrorMsg;
 
public function printcheckBackendDAEWithErrorMsg"function: printcheckBackendDAEWithErrorMsg
  author: Frenkel TUD
  helper for checkDEALowWithErrorMsg"
  input list<tuple<DAE.Exp,list<DAE.ComponentRef>>> inExpCrefs;
  input list<BackendDAE.Equation> inWrongEqns;
algorithm   
  _ := match (inExpCrefs,inWrongEqns)
    local
      DAE.Exp e;
      list<DAE.ComponentRef> crefs;
      list<tuple<DAE.Exp,list<DAE.ComponentRef>>> res;
      list<String> strcrefs;
      String crefstring, expstr,scopestr;
      BackendDAE.Equation eqn;
      list<BackendDAE.Equation> wrongEqns;
    
    case ({},{})  then ();
    
    case ({},eqn::wrongEqns)
      equation
        printEqnSizeError(eqn);
        printcheckBackendDAEWithErrorMsg({},wrongEqns);
      then ();
    
    case (((e,crefs))::res,wrongEqns)
      equation
        strcrefs = List.map(crefs,ComponentReference.crefStr);
        crefstring = stringDelimitList(strcrefs,", ");
        expstr = ExpressionDump.printExpStr(e);
        scopestr = stringAppendList({crefstring," from Expression: ",expstr});
        Error.addMessage(Error.LOOKUP_VARIABLE_ERROR, {scopestr,"BackendDAE object"});
        printcheckBackendDAEWithErrorMsg(res,wrongEqns);
      then
        ();
  end match;
end printcheckBackendDAEWithErrorMsg;

protected function printEqnSizeError"function: printEqnSizeError
  author: Frenkel TUD 2010-12"
    input BackendDAE.Equation inEqn;
algorithm
  _ := matchcontinue(inEqn)
  local 
    BackendDAE.Equation eqn;
    DAE.Exp e1, e2;
    DAE.ComponentRef cr;
    DAE.Type t1,t2;
    String eqnstr, t1str, t2str, tstr;
    DAE.ElementSource source;
    case (eqn as BackendDAE.EQUATION(exp=e1,scalar=e2,source=source))
      equation
        eqnstr = BackendDump.equationStr(eqn);
        t1 = Expression.typeof(e1);
        t2 = Expression.typeof(e2);
        t1str = Types.unparseType(t1);
        t2str = Types.unparseType(t2);
        tstr = stringAppendList({t1str," != ", t2str});
        Error.addSourceMessage(Error.EQUATION_TYPE_MISMATCH_ERROR, {eqnstr,tstr}, DAEUtil.getElementSourceFileInfo(source));
      then ();
    case (eqn as BackendDAE.SOLVED_EQUATION(componentRef=cr,exp=e1,source=source))
      equation
        eqnstr = BackendDump.equationStr(eqn);
        t1 = Expression.typeof(e1);
        t2 = ComponentReference.crefLastType(cr);
        t1str = Types.unparseType(t1);
        t2str = Types.unparseType(t2);
        tstr = stringAppendList({t1str," != ", t2str});
        Error.addSourceMessage(Error.EQUATION_TYPE_MISMATCH_ERROR, {eqnstr,tstr}, DAEUtil.getElementSourceFileInfo(source));
      then ();
      //
    case eqn then ();
  end matchcontinue;
end printEqnSizeError;
      
public function checkBackendDAE "function: checkBackendDAE
  author: Frenkel TUD
  This function checks the BackendDAE object if
  -  all component refercences used in the expressions are 
     part of the BackendDAE object.
  -  all variables that are reinit are states
  Returns all component references which not part of the BackendDAE object."
  input BackendDAE.BackendDAE inBackendDAE;
  output list<tuple<DAE.Exp,list<DAE.ComponentRef>>> outExpCrefs;
  output list<BackendDAE.Equation> outWrongEqns;
algorithm
  (outExpCrefs,outWrongEqns) := matchcontinue (inBackendDAE)
    local
      BackendDAE.Variables vars1,vars2,allvars;
      EquationArray eqns,reqns,ieqns;
      list<WhenClause> whenClauseLst;      
      list<Var> varlst1,varlst2,allvarslst;
      list<tuple<DAE.Exp,list<DAE.ComponentRef>>> expcrefs,expcrefs1,expcrefs2,expcrefs3,expcrefs4,expcrefs5;
      list<BackendDAE.Equation> wrongEqns,wrongEqns1,wrongEqns2;

    
    case (BackendDAE.DAE(eqs=BackendDAE.EQSYSTEM(orderedVars = vars1,orderedEqs = eqns)::{},shared=BackendDAE.SHARED(knownVars = vars2,initialEqs = ieqns,removedEqs = reqns,
          eventInfo = BackendDAE.EVENT_INFO(whenClauseLst=whenClauseLst))))
      equation
        varlst1 = varList(vars1);
        varlst2 = varList(vars2);
        allvarslst = listAppend(varlst1,varlst2);
        allvars = listVar(allvarslst);
        ((_,expcrefs)) = traverseBackendDAEExpsVars(vars1,checkBackendDAEExp,(allvars,{}));
        ((_,expcrefs1)) = traverseBackendDAEExpsVars(vars2,checkBackendDAEExp,(allvars,expcrefs));
        ((_,expcrefs2)) = traverseBackendDAEExpsEqns(eqns,checkBackendDAEExp,(allvars,expcrefs1));
        ((_,expcrefs3)) = traverseBackendDAEExpsEqns(reqns,checkBackendDAEExp,(allvars,expcrefs2));
        ((_,expcrefs4)) = traverseBackendDAEExpsEqns(ieqns,checkBackendDAEExp,(allvars,expcrefs3));
        (_,(_,expcrefs5)) = BackendDAETransform.traverseBackendDAEExpsWhenClauseLst(whenClauseLst,checkBackendDAEExp,(allvars,expcrefs4));
        wrongEqns = BackendEquation.traverseBackendDAEEqns(eqns,checkEquationSize,{});
        wrongEqns1 = BackendEquation.traverseBackendDAEEqns(reqns,checkEquationSize,wrongEqns);
        wrongEqns2 = BackendEquation.traverseBackendDAEEqns(ieqns,checkEquationSize,wrongEqns1);
      then
        (expcrefs5,wrongEqns2);
    
    else
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAEUtil.checkBackendDAE failed");
      then
        fail();
  end matchcontinue;
end checkBackendDAE;

protected function checkBackendDAEExp
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<tuple<DAE.Exp,list<DAE.ComponentRef>>>>> inTpl;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables,list<tuple<DAE.Exp,list<DAE.ComponentRef>>>>> outTpl;
algorithm
  outTpl :=
  matchcontinue inTpl
    local  
      DAE.Exp exp;
      BackendDAE.Variables vars;
      list<DAE.ComponentRef> crefs;
      list<tuple<DAE.Exp,list<DAE.ComponentRef>>> lstExpCrefs,lstExpCrefs1;
    case ((exp,(vars,lstExpCrefs)))
      equation
        ((_,(_,crefs))) = Expression.traverseExp(exp,traversecheckBackendDAEExp,(vars,{}));
        lstExpCrefs1 = Util.if_(listLength(crefs)>0,(exp,crefs)::lstExpCrefs,lstExpCrefs);
       then
        ((exp,(vars,lstExpCrefs1)));
    case _ then inTpl;
  end matchcontinue;
end checkBackendDAEExp;

protected function traversecheckBackendDAEExp
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<DAE.ComponentRef>>> inTuple;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables,list<DAE.ComponentRef>>> outTuple;
algorithm
  outTuple := matchcontinue(inTuple)
    local
      DAE.Exp e,e1;
      BackendDAE.Variables vars,vars1;
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crefs,crefs1;
      list<DAE.Exp> expl;
      list<DAE.Var> varLst;
      list<Var> backendVars;
      DAE.ReductionIterators riters;
    
    // special case for time, it is never part of the equation system  
    case ((e as DAE.CREF(componentRef = DAE.CREF_IDENT(ident="time")),(vars,crefs)))
      then ((e, (vars,crefs)));
    
    // Special Case for Records
    case ((e as DAE.CREF(componentRef = cr,ty= DAE.T_COMPLEX(varLst=varLst,complexClassType=ClassInf.RECORD(_))),(vars,crefs)))
      equation
        expl = List.map1(varLst,Expression.generateCrefsExpFromExpVar,cr);
        ((_,(vars1,crefs1))) = Expression.traverseExpList(expl,traversecheckBackendDAEExp,(vars,crefs));
      then
        ((e, (vars1,crefs1)));

    // Special Case for Arrays
    case ((e as DAE.CREF(ty = DAE.T_ARRAY(ty=_)),(vars,crefs)))
      equation
        ((e1,(_,true))) = extendArrExp((e,(NONE(),false)));
        ((_,(vars1,crefs1))) = Expression.traverseExp(e1,traversecheckBackendDAEExp,(vars,crefs));
      then
        ((e, (vars1,crefs1)));
    
    // case for Reductions    
    case ((e as DAE.REDUCTION(iterators = riters),(vars,crefs)))
      equation
        // add idents to vars
        backendVars = List.map(riters,makeIterVariable);
        vars = BackendVariable.addVars(backendVars,vars);
      then
        ((e, (vars,crefs)));
    
    // case for functionpointers    
    case ((e as DAE.CREF(ty=DAE.T_FUNCTION_REFERENCE_FUNC(builtin=_)),(vars,crefs)))
      then
        ((e, (vars,crefs)));
    
    case ((e as DAE.CREF(componentRef = cr),(vars,crefs)))
      equation
         (_,_) = BackendVariable.getVar(cr, vars);
      then
        ((e, (vars,crefs)));
    
    case ((e as DAE.CREF(componentRef = cr),(vars,crefs)))
      equation
         failure((_,_) = BackendVariable.getVar(cr, vars));
      then
        ((e, (vars,cr::crefs)));
    
    case _ then inTuple;
  end matchcontinue;
end traversecheckBackendDAEExp;

protected function makeIterVariable
  input DAE.ReductionIterator iter;
  output Var backendVar;
protected
  String name;
  DAE.ComponentRef cr;
algorithm
  name := Expression.reductionIterName(iter);
  cr := ComponentReference.makeCrefIdent(name,DAE.T_INTEGER_DEFAULT,{});
  backendVar := BackendDAE.VAR(cr,BackendDAE.VARIABLE(),DAE.BIDIR(),DAE.NON_PARALLEL(),DAE.T_INTEGER_DEFAULT,NONE(),NONE(),{},
                     DAE.emptyElementSource,NONE(),NONE(),DAE.NON_CONNECTOR());
end makeIterVariable;

protected function checkEquationSize"function: checkEquationSize
  author: Frenkel TUD 2010-12
  - check if the left hand side and the rigth hand side have equal types."
  input tuple<BackendDAE.Equation, list<BackendDAE.Equation>> inTpl;
  output tuple<BackendDAE.Equation, list<BackendDAE.Equation>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local 
    BackendDAE.Equation e;
    list<BackendDAE.Equation> wrongEqns,wrongEqns1;
    DAE.Exp e1, e2;
    DAE.ComponentRef cr;
    DAE.Type t1,t2;
    Boolean b;
    case ((e as BackendDAE.EQUATION(exp=e1,scalar=e2),wrongEqns))
      equation
        t1 = Expression.typeof(e1);
        t2 = Expression.typeof(e2);
        b = Expression.equalTypes(t1,t2);
        wrongEqns1 = List.consOnTrue(not b,e,wrongEqns);
      then ((e,wrongEqns1));

    case ((e as BackendDAE.SOLVED_EQUATION(componentRef=cr,exp=e1),wrongEqns))
      equation
        t1 = Expression.typeof(e1);
        t2 = ComponentReference.crefLastType(cr);
        b = Expression.equalTypes(t1,t2);
        wrongEqns1 = List.consOnTrue(not b,e,wrongEqns);
      then ((e,wrongEqns1));
       
      //
    case _ then inTpl;
  end matchcontinue;
end checkEquationSize;

public function checkAssertCondition "Succeds if condition of assert is not constant false"
  input DAE.Exp cond;
  input DAE.Exp message;
  input DAE.Exp level;
algorithm
  _ := matchcontinue(cond,message,level)
    local 
      String messageStr;
    case(_, _, _)
      equation
        // Don't check assertions when checking models
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
      then ();
    case (_,_,_)
      equation
        false = Expression.isConstFalse(cond);
      then ();
    case (_,_,_)
      equation
        failure(DAE.ENUM_LITERAL(index=1) = level);
      then ();
    case(_,_,_)
      equation
        true = Expression.isConstFalse(cond);
        messageStr = ExpressionDump.printExpStr(message);
        Error.addMessage(Error.ASSERT_CONSTANT_FALSE_ERROR,{messageStr});
      then fail();
  end matchcontinue;
end checkAssertCondition;


public function expandAlgorithmsbyInitStmts 
"function: expandAlgorithmsbyInitStmts
  This function expands algorithm sections by initial statements.
  - A non-discrete variable is initialized with its start value (i.e. the value of the start-attribute). 
  - A discrete variable v is initialized with pre(v)."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
algorithm
  outDAE := mapEqSystem(inDAE,expandAlgorithmsbyInitStmts1);
end expandAlgorithmsbyInitStmts;

protected function expandAlgorithmsbyInitStmts1
"function: expandAlgorithmsbyInitStmt1
  This function expands algorithm sections by initial statements.
  - A non-discrete variable is initialized with its start value (i.e. the value of the start-attribute). 
  - A discrete variable v is initialized with pre(v).
  Helper function to expandAlgorithmsbyInitStmts.
"
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
algorithm
  (osyst,oshared) := match (syst,shared)
 local 
  BackendDAE.Variables ordvars;
  EquationArray ordeqns;
  BackendDAE.EqSystem eqs; 
   case(eqs as BackendDAE.EQSYSTEM(orderedVars=ordvars,orderedEqs=ordeqns),_)
   equation
     (ordeqns,_) = BackendEquation.traverseBackendDAEEqnsWithUpdate(ordeqns,expandAlgorithmsbyInitStmtsHelper,ordvars);
   then(eqs,shared);    
   end match;
end expandAlgorithmsbyInitStmts1;

protected function expandAlgorithmsbyInitStmtsHelper
"function: expandAlgorithmsbyInitStmt
  This function expands algorithm sections by initial statements.
  - A non-discrete variable is initialized with its start value (i.e. the value of the start-attribute). 
  - A discrete variable v is initialized with pre(v).
  Helper function to expandAlgorithmsbyInitStmts1.
"
  input tuple<BackendDAE.Equation,BackendDAE.Variables> inTpl;
  output tuple<BackendDAE.Equation,BackendDAE.Variables> outTpl;  
algorithm
  outTpl := matchcontinue(inTpl)
    local
      DAE.Algorithm alg;
      DAE.Algorithm algExpanded;
      BackendDAE.Equation eqn;
      BackendDAE.Variables vars;
      Integer size;
      list<DAE.Exp> outputs;
      DAE.ElementSource source;
      list<DAE.ComponentRef> crlst;
    case((eqn as BackendDAE.ALGORITHM(size=size,alg=alg,source=source),vars))
      equation
        crlst = CheckModel.algorithmOutputs(alg);
        outputs = List.map(crlst,Expression.crefExp);
        algExpanded = expandAlgorithmStmts(alg,outputs,vars);
      then 
        ((BackendDAE.ALGORITHM(size,algExpanded,source), vars));
    else
      then inTpl;     
  end matchcontinue;
end expandAlgorithmsbyInitStmtsHelper;


protected function expandAlgorithmStmts
"function: expandAlgorithmStmts
  This function expands algorithm sections by initial statements.
  - A non-discrete variable is initialized with its start value (i.e. the value of the start-attribute). 
  - A discrete variable v is initialized with pre(v).
  Helper function to expandAlgorithmsbyInitStmts1."
  input DAE.Algorithm inAlg;
  input list<DAE.Exp> inOutputs;
  input BackendDAE.Variables inVars;
  output DAE.Algorithm outAlg;
algorithm
   outAlg := matchcontinue(inAlg, inOutputs, inVars)
 local
   DAE.Algorithm alg;
   DAE.Exp out,initExp;
   list<DAE.Exp> rest;
   DAE.ComponentRef cref;
   Var var;
   DAE.Statement stmt;
   DAE.Type type_;
   list<DAE.Statement> statements,statements1;
   case(alg,{},_) then (alg);
   case(alg,out::rest,_)
     equation
       cref = Expression.expCref(out);
       type_ = Expression.typeof(out);
       type_ = Expression.arrayEltType(type_);
       (var::_,_) = BackendVariable.getVar(cref, inVars);
       true = BackendVariable.isVarDiscrete(var);
       initExp = Expression.makeBuiltinCall("pre", {out}, type_);
       stmt = Algorithm.makeAssignment(DAE.CREF(cref,type_), DAE.PROP(type_,DAE.C_VAR()), initExp, DAE.PROP(type_,DAE.C_VAR()), DAE.dummyAttrVar, SCode.NON_INITIAL(), DAE.emptyElementSource);
       (DAE.ALGORITHM_STMTS(statements)) = expandAlgorithmStmts(alg,rest,inVars);
       statements1 = listAppend({stmt},statements);
     then (DAE.ALGORITHM_STMTS(statements1));
   case(alg,out::rest,_)
     equation
       cref = Expression.expCref(out);
       type_ = Expression.typeof(out);
       type_ = Expression.arrayEltType(type_);
       (var::_,_) = BackendVariable.getVar(cref, inVars);
       false = BackendVariable.isVarDiscrete(var);
       initExp = Expression.makeBuiltinCall("$_start", {out}, type_);
       stmt = Algorithm.makeAssignment(DAE.CREF(cref,type_), DAE.PROP(type_,DAE.C_VAR()), initExp, DAE.PROP(type_,DAE.C_VAR()), DAE.dummyAttrVar, SCode.NON_INITIAL(), DAE.emptyElementSource);
       (DAE.ALGORITHM_STMTS(statements)) = expandAlgorithmStmts(alg,rest,inVars);
       statements1 = listAppend({stmt},statements);
     then (DAE.ALGORITHM_STMTS(statements1));
   end matchcontinue;
end expandAlgorithmStmts;




/************************************************************
  Util function at Backend using for lowering and other stuff
 ************************************************************/

public  function createEmptyBackendDAE
" function: createEmptyBackendDAE
  author: wbraun
  Copy the dae to avoid changes in
  vectors."
  input BackendDAEType inBDAEType;
  output BackendDAE.BackendDAE outBDAE;
protected 
  BackendDAE.Variables emptyvars;
  EquationArray emptyEqns;
  BackendDAE.Variables emptyAliasVars;
  array<DAE.Constraint> constrs;
  array<DAE.ClassAttributes> clsAttrs;
  Env.Cache cache; 
  DAE.FunctionTree funcTree;
algorithm
  emptyvars :=  emptyVars();
  emptyEqns := listEquation({});
  emptyAliasVars := emptyVars();
  constrs := listArray({});
  clsAttrs := listArray({});
  cache := Env.emptyCache();
  funcTree := DAEUtil.avlTreeNew();
  outBDAE := BackendDAE.DAE({BackendDAE.EQSYSTEM(
                              emptyvars,
                              emptyEqns,
                              NONE(),
                              NONE(),
                              BackendDAE.NO_MATCHING()
                            )},
                            BackendDAE.SHARED(
                              emptyvars,
                              emptyvars, 
                              emptyAliasVars, 
                              emptyEqns, 
                              emptyEqns, 
                              constrs,
                              clsAttrs,
                              cache, 
                              {},
                              funcTree,
                              BackendDAE.EVENT_INFO({},{},{},{},0),
                              {},
                              inBDAEType,
                              {}
                            )
                          );
end createEmptyBackendDAE;


public  function copyBackendDAE
" function: copyBackendDAE
  author: Frenkel TUD, wbraun
  Copy the dae to avoid changes in
  vectors."
  input BackendDAE.BackendDAE inBDAE;
  output BackendDAE.BackendDAE outBDAE;
algorithm
  outBDAE:=
  match (inBDAE)
    local
      EqSystems eqns;
      BackendDAE.Shared shared,shared1;
      BackendDAE.BackendDAE bDAE;
    case (bDAE as BackendDAE.DAE(eqs=eqns, shared=shared))
      equation
        BackendDAE.DAE(eqs=eqns) = mapEqSystem(bDAE, copyBackendDAEEqSystem);
        shared1 = copyBackendDAEShared(shared);
      then
        BackendDAE.DAE(eqns,shared1);
  end match;
end copyBackendDAE;

public  function copyBackendDAEEqSystem
" function: copyBackendDAE
  author: Frenkel TUD, wbraun
  Copy the dae to avoid changes in
  vectors."
  input BackendDAE.EqSystem inSysts;
  input BackendDAE.Shared inShared;
  output BackendDAE.EqSystem outSysts;
  output BackendDAE.Shared outShared;
algorithm
  (outSysts, outShared) :=
  match (inSysts,inShared)
    local
      BackendDAE.Variables ordvars,ordvars1;
      EquationArray eqns,eqns1;
      Option<BackendDAE.IncidenceMatrix> m,mT,m1,mT1;
      BackendDAE.Matching matching,matching1;
      BackendDAE.Shared shared;
    case (BackendDAE.EQSYSTEM(ordvars,eqns,m,mT,matching),shared)
      equation
        // copy varibales
        ordvars1 = BackendVariable.copyVariables(ordvars);
        // copy equations
        eqns1 = BackendEquation.copyEquationArray(eqns);
        m1 = copyIncidenceMatrix(m);
        mT1 = copyIncidenceMatrix(mT);
        matching1 = copyMatching(matching);
      then
        (BackendDAE.EQSYSTEM(ordvars1,eqns1,m1,mT1,matching1),shared);
  end match;
end copyBackendDAEEqSystem;

public  function copyBackendDAEShared
" function: copyBackendDAEShared
  author: Frenkel TUD, wbraun
  Copy the shared part of an BackendDAE to avoid changes in
  vectors."
  input BackendDAE.Shared inShared;
  output BackendDAE.Shared outShared;
algorithm
  outShared:=
  match (inShared)
    local
      BackendDAE.Variables knvars,exobj,knvars1,exobj1,av;
      EquationArray remeqns,inieqns,remeqns1,inieqns1;
      array<DAE.Constraint> constrs,constrs1;
      list<DAE.Constraint> lstconstrs;
      array<DAE.ClassAttributes> clsAttrs,clsAttrs1;
      list<DAE.ClassAttributes> lstattrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcTree; 
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
    case (BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs))
      equation
        knvars1 = BackendVariable.copyVariables(knvars);
        exobj1 = BackendVariable.copyVariables(exobj);
        inieqns1 = BackendEquation.copyEquationArray(inieqns);
        remeqns1 = BackendEquation.copyEquationArray(remeqns);      
       lstconstrs = arrayList(constrs);
       constrs1 = listArray(lstconstrs);    
       lstattrs = arrayList(clsAttrs);
       clsAttrs1 = listArray(lstattrs);          
      then
        BackendDAE.SHARED(knvars1,exobj,av,inieqns1,remeqns1,constrs1,clsAttrs1,cache,env,funcTree,einfo,eoc,btp,symjacs);
  end match;
end copyBackendDAEShared;

public function copyMatching
  input BackendDAE.Matching inMatching;
  output BackendDAE.Matching outMatching;
algorithm
  outMatching := match (inMatching)
    local
      array<Integer> ass1, cass1, ass2, cass2;
      BackendDAE.StrongComponents comps;
    case (BackendDAE.NO_MATCHING()) then BackendDAE.NO_MATCHING();
    case (BackendDAE.MATCHING(ass1=ass1,ass2=ass2,comps=comps))
      equation
        cass1 = arrayCreate(arrayLength(ass1),0);
        _ = Util.arrayCopy(ass1, cass1);
        cass2 = arrayCreate(arrayLength(ass2),0);
        _ = Util.arrayCopy(ass2, cass2);
      then BackendDAE.MATCHING(cass1,cass2,comps); 
  end match;
end copyMatching;

public function addBackendDAESharedJacobian
" function: addBackendDAESharedJacobian
  author:  wbraun"
  input BackendDAE.SymbolicJacobian inSymJac;
  input BackendDAE.SparsePattern inSparsePattern;
  input BackendDAE.SparseColoring inSparseColoring;    
  input BackendDAE.Shared inShared;
  output BackendDAE.Shared outShared;
algorithm
  outShared:=
  match (inSymJac, inSparsePattern, inSparseColoring, inShared)
    local
      BackendDAE.Variables knvars,exobj,av;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcTree; 
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
    case (_,_,_,BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs))
      equation
        symjacs = {(SOME(inSymJac),inSparsePattern,inSparseColoring),(NONE(),({},({},{})),{}),(NONE(),({},({},{})),{}),(NONE(),({},({},{})),{})};
      then
        BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs);
  end match;
end addBackendDAESharedJacobian;

public function addBackendDAESharedJacobians
" function: addBackendDAESharedJacobians
  author:  wbraun"
  input BackendDAE.SymbolicJacobians inSymJac; 
  input BackendDAE.Shared inShared;
  output BackendDAE.Shared outShared;
algorithm
  outShared:=
  match (inSymJac, inShared)
    local
      BackendDAE.Variables knvars,exobj,av;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs; 
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcTree; 
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
    case (_,BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs))
      then
        BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,inSymJac);
  end match;
end addBackendDAESharedJacobians;

public function addBackendDAESharedJacobianSparsePattern
" function: addBackendDAESharedJacobianSparsePattern
  author:  wbraun"
  input BackendDAE.SparsePattern inSparsePattern;
  input BackendDAE.SparseColoring inSparseColoring;
  input Integer inIndex;
  input BackendDAE.Shared inShared;
  output BackendDAE.Shared outShared;
algorithm
  outShared:=
  match (inSparsePattern, inSparseColoring, inIndex, inShared)
    local
      BackendDAE.Variables knvars,exobj,av;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcTree; 
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
      Option<BackendDAE.SymbolicJacobian> symJac;
    case (_, _, _, BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs))
      equation
        ((symJac,_,_)) = listGet(symjacs, inIndex);
        symjacs = List.set(symjacs, inIndex, ((symJac, inSparsePattern, inSparseColoring)));
      then
        BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs);
  end match;
end addBackendDAESharedJacobianSparsePattern;

public function addBackendDAEKnVars
" function: addBackendDAEKnVars
  That function replace the KnownVars in BackendDAE.
  author:  wbraun"
  input BackendDAE.Variables inKnVars;
  input BackendDAE.BackendDAE inBDAE;
  output BackendDAE.BackendDAE outBDAE;
algorithm
  outBDAE := match (inKnVars, inBDAE)
    local
      BackendDAE.Variables exobj,av;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs; 
      Env.Cache cache;
      Env.Env env;
      DAE.FunctionTree funcTree; 
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
      EqSystems eqs;
    case (_,(BackendDAE.DAE(eqs=eqs,shared=BackendDAE.SHARED(_,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs))))
      then (BackendDAE.DAE(eqs,BackendDAE.SHARED(inKnVars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,funcTree,einfo,eoc,btp,symjacs)));
  end match;
end addBackendDAEKnVars;

public function addBackendDAEEqSystem "function addBackendDAEEqSystem
  author: lochel
  This function adds a EqSystem to BackendDAE."
  input BackendDAE.BackendDAE inDAE;
  input BackendDAE.EqSystem inAddEqSystem;
  output BackendDAE.BackendDAE outDAE;
algorithm
  outDAE := match(inDAE, inAddEqSystem)
    local
      list<BackendDAE.EqSystem> eqs;
      BackendDAE.Shared shared;
      BackendDAE.EqSystem addEqSystem;
      
    case(BackendDAE.DAE(eqs=eqs, shared=shared), addEqSystem) equation
      eqs = listAppend(eqs, {addEqSystem});
    then(BackendDAE.DAE(eqs, shared));
      
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/BackendDAEUtil.mo: function addBackendDAEEqSystem failed"});
    then fail();
  end match;
end addBackendDAEEqSystem;

public function addBackendDAEFunctionTree
" function: addBackendDAEFunctionTree
  That function replace the FunctionTree in BackendDAE.
  author:  wbraun"
  input DAE.FunctionTree inFunctionTree;
  input BackendDAE.BackendDAE inBDAE;
  output BackendDAE.BackendDAE outBDAE;
algorithm
  outBDAE := match (inFunctionTree, inBDAE)
    local
      BackendDAE.Variables knvars,exobj,av;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;  
      Env.Cache cache;
      Env.Env env;      
      BackendDAE.EventInfo einfo;
      ExternalObjectClasses eoc;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
      EqSystems eqs;
    case (_,(BackendDAE.DAE(eqs=eqs,shared=BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,_,einfo,eoc,btp,symjacs))))
      then (BackendDAE.DAE(eqs,BackendDAE.SHARED(knvars,exobj,av,inieqns,remeqns,constrs,clsAttrs,cache,env,inFunctionTree,einfo,eoc,btp,symjacs)));
  end match;
end addBackendDAEFunctionTree;

public function addVarsToEqSystem
  input BackendDAE.EqSystem syst;
  input list<Var> varlst;
  output BackendDAE.EqSystem osyst;
algorithm
  osyst := match (syst,varlst)
    local
      BackendDAE.Variables vars;
      EquationArray eqs;
      Option<BackendDAE.IncidenceMatrix> m,mT;
      BackendDAE.Matching matching;
    case (BackendDAE.EQSYSTEM(vars, eqs, m, mT, matching),_)
      equation
        vars = BackendVariable.addVars(varlst, vars);
      then BackendDAE.EQSYSTEM(vars, eqs, m, mT, matching);
  end match;
end addVarsToEqSystem;

public function addDummyStateIfNeeded
"function addDummyStateIfNeeded
  author: Frenkel TUD 2012-09
  adds a dummy state if dae contains no states"
  input BackendDAE.BackendDAE inBackendDAE;
  output BackendDAE.BackendDAE outBackendDAE;
protected
  BackendDAE.EqSystems systs;
  BackendDAE.Shared shared;
  Boolean daeContainsNoStates;  
algorithm
  BackendDAE.DAE(eqs=systs,shared=shared) := inBackendDAE;
  // check if the DAE has states
  daeContainsNoStates := addDummyStateIfNeeded1(systs);
  // adrpo: add the dummy derivative state ONLY IF the DAE contains no states
  systs := Debug.bcallret1(daeContainsNoStates,addDummyState,systs,systs);
  outBackendDAE := Util.if_(daeContainsNoStates,BackendDAE.DAE(systs,shared),inBackendDAE);
end addDummyStateIfNeeded;

protected function addDummyStateIfNeeded1
  input BackendDAE.EqSystems iSysts;
  output Boolean oContainsNoStates;
algorithm
  oContainsNoStates := match(iSysts)
    local
      BackendDAE.EqSystems systs;
      BackendDAE.Variables vars;
      Boolean containsNoStates;
    case ({}) then true;
    case (BackendDAE.EQSYSTEM(orderedVars = vars)::systs)
      equation
        containsNoStates = BackendVariable.traverseBackendDAEVarsWithStop(vars, traverserVaraddDummyStateIfNeeded, true);
        containsNoStates = Debug.bcallret1(containsNoStates,addDummyStateIfNeeded1,systs,containsNoStates);
      then
        containsNoStates;
  end match;
end addDummyStateIfNeeded1;

protected function traverserVaraddDummyStateIfNeeded
 input tuple<BackendDAE.Var, Boolean> inTpl;
 output tuple<BackendDAE.Var, Boolean, Boolean> outTpl;
algorithm
  outTpl:= match (inTpl)
    local
      BackendDAE.Var v;
      Boolean b;
    case ((v as BackendDAE.VAR(varKind=BackendDAE.STATE()),_))
      then ((v,false,false));
    case ((v,b)) then ((v,b,b));
  end match;
end traverserVaraddDummyStateIfNeeded;

protected function addDummyState
"function: addDummyState
  In order for the solver to work correctly at least one state variable
  must exist in the equation system. This function therefore adds a
  dummy state variable and an equation for that variable."
  input BackendDAE.EqSystems isysts;
  output BackendDAE.EqSystems osysts;
protected
  DAE.ComponentRef cr;
  BackendDAE.Var v;
  BackendDAE.Variables vars;
  DAE.Exp exp;
  BackendDAE.Equation eqn;
  BackendDAE.EquationArray eqns;
  array<Integer> ass;
  BackendDAE.EqSystem syst;
algorithm
  // generate dummy state
  (v,cr) := BackendVariable.createDummyVar();

  // generate vars
  vars := listVar({v});
  /*
   * adrpo: after a bit of talk with Francesco Casella & Peter Aronsson we will add der($dummy) = 0;
   */
  exp := Expression.crefExp(cr);
  eqn := BackendDAE.EQUATION(DAE.CALL(Absyn.IDENT("der"),{exp},DAE.callAttrBuiltinReal),DAE.RCONST(0.0), DAE.emptyElementSource);
  eqns := listEquation({eqn});
  // generate equationsystem
  ass := listArray({1});
  syst := BackendDAE.EQSYSTEM(vars,eqns,NONE(),NONE(),BackendDAE.MATCHING(ass,ass,{BackendDAE.SINGLEEQUATION(1,1)}));
  // add system to list of systems
  osysts := syst::isysts;
end addDummyState;

public function calculateSizes "function: calculateSizes
  author: PA
  Calculates the number of state variables, nx,
  the number of algebraic variables, ny
  and the number of parameters/constants, np.
  inputs:  BackendDAE
  outputs: (int, /* nx */
            int, /* ny */
            int, /* np */
            int  /* ng */
            int) next"
  input BackendDAE.BackendDAE inBackendDAE;
  output Integer outnx        "number of states";
  output Integer outny        "number of alg. vars";
  output Integer outnp        "number of parameters";
  output Integer outng        "number of zerocrossings";
  output Integer outng_sample "number of zerocrossings that are samples";
  output Integer outnext      "number of external objects";
  // nx cannot be strings
  output Integer outny_string "number of alg.vars which are strings";
  output Integer outnp_string "number of parameters which are strings";
  // nx cannot be int
  output Integer outny_int    "number of alg.vars which are ints";
  output Integer outnp_int    "number of parameters which are ints";
  // nx cannot be int
  output Integer outny_bool   "number of alg.vars which are bools";
  output Integer outnp_bool   "number of parameters which are bools";
algorithm
  (outnx,outny,outnp,outng,outng_sample,outnext, outny_string, outnp_string, outny_int, outnp_int, outny_bool, outnp_bool):=
  match (inBackendDAE)
    local
      Integer np,ng,nsam,nx,ny,nx_1,ny_1,next,ny_string,np_string,ny_1_string,np_int,np_bool,ny_int,ny_1_int,ny_bool,ny_1_bool;
      BackendDAE.Variables vars,knvars,extvars;
      list<WhenClause> wc;
      list<ZeroCrossing> zc;
      Integer numberOfRelations;
    
    case (BackendDAE.DAE(eqs=BackendDAE.EQSYSTEM(orderedVars = vars)::{},shared=BackendDAE.SHARED(knownVars = knvars, externalObjects = extvars,
                 eventInfo = BackendDAE.EVENT_INFO(whenClauseLst = wc,
                                        zeroCrossingLst = zc,relationsNumber=numberOfRelations ))))
      equation
        // input variables are put in the known var list, but they should be counted by the ny counter
        next = BackendVariable.varsSize(extvars);
        ((np,np_string,np_int, np_bool)) = BackendVariable.traverseBackendDAEVars(knvars,calculateParamSizes,(0,0,0,0));
        (ng,nsam) = calculateNumberZeroCrossings(zc, 0, 0);
        ((nx,ny,ny_string,ny_int, ny_bool)) = BackendVariable.traverseBackendDAEVars(vars,calculateVarSizes,(0, 0, 0, 0, 0));
        ((nx_1,ny_1,ny_1_string,ny_1_int, ny_1_bool)) = BackendVariable.traverseBackendDAEVars(knvars,calculateVarSizes,(nx, ny, ny_string, ny_int, ny_bool));
      then
        (nx_1,ny_1,np,numberOfRelations,nsam,next,ny_1_string, np_string, ny_1_int, np_int, ny_1_bool, np_bool);
  end match;
end calculateSizes;

public function numberOfZeroCrossings "function: numberOfZeroCrossings
  author: Frenkel TUD"
  input BackendDAE.BackendDAE inBackendDAE;
  output Integer outng        "number of zerocrossings";
  output Integer outng_sample "number of zerocrossings that are samples";
  output Integer outng_rel    "number of relation in zerocrossings";  
algorithm
  (outng,outng_sample,outng_rel):=
  match (inBackendDAE)
    local
      Integer ng,nsam, ngrel;
      list<ZeroCrossing> zc, samples;
    case (BackendDAE.DAE(shared=BackendDAE.SHARED(eventInfo = BackendDAE.EVENT_INFO(zeroCrossingLst = zc, sampleLst =samples, relationsNumber=ngrel))))
      equation
        ng = listLength(zc);
        nsam = listLength(samples);
      then
        (ng,nsam,ngrel);
  end match;
end numberOfZeroCrossings;

protected function calculateNumberZeroCrossings
  input list<ZeroCrossing> zcLst;
  input Integer inZc_index;
  input Integer inSample_index;
  output Integer zc;
  output Integer sample;
algorithm
  (zc,sample) := matchcontinue (zcLst,inZc_index,inSample_index)
    local
      list<ZeroCrossing> xs;
      Integer sample_index, zc_index;
    
    case ({},zc_index,sample_index) then (zc_index,sample_index);

    case (BackendDAE.ZERO_CROSSING(relation_ = DAE.CALL(path = Absyn.IDENT(name = "sample"))) :: xs,zc_index,sample_index)
      equation
        sample_index = sample_index + 1;
        zc_index = zc_index + 1;
        (zc,sample) = calculateNumberZeroCrossings(xs,zc_index,sample_index);
      then (zc,sample);

    case (BackendDAE.ZERO_CROSSING(relation_ = DAE.RELATION(operator = _), occurEquLst = _) :: xs,zc_index,sample_index)
      equation
        zc_index = zc_index + 1;
        (zc,sample) = calculateNumberZeroCrossings(xs,zc_index,sample_index);
      then (zc,sample);

    case (BackendDAE.ZERO_CROSSING(relation_ = DAE.LBINARY(operator = _), occurEquLst = _) :: xs,zc_index,sample_index)
      equation
        zc_index = zc_index + 1;
        (zc,sample) = calculateNumberZeroCrossings(xs,zc_index,sample_index);
      then (zc,sample);

    case (BackendDAE.ZERO_CROSSING(relation_ = DAE.LUNARY(operator = _), occurEquLst = _) :: xs,zc_index,sample_index)
      equation
        zc_index = zc_index + 1;
        (zc,sample) = calculateNumberZeroCrossings(xs,zc_index,sample_index);
      then (zc,sample);


    case (_,_,_)
      equation
        print("- BackendDAEUtil.calculateNumberZeroCrossings failed\n");
      then
        fail();

  end matchcontinue;
end calculateNumberZeroCrossings;

protected function calculateParamSizes "function: calculateParamSizes
  author: PA
  Helper function to calculateSizes"
  input tuple<Var, tuple<Integer,Integer,Integer,Integer>> inTpl;
  output tuple<Var, tuple<Integer,Integer,Integer,Integer>> outTpl;
algorithm
  outTpl :=
  matchcontinue (inTpl)
    local
      Integer s1,s2,s3, s4;
      Var var;
    case ((var,(s1,s2,s3,s4)))
      equation
        true = BackendVariable.isBoolParam(var);
      then
        ((var,(s1,s2,s3,s4 + 1)));
    case ((var,(s1,s2,s3,s4)))
      equation
        true = BackendVariable.isIntParam(var);
      then
        ((var,(s1,s2,s3 + 1,s4)));
    case ((var,(s1,s2,s3,s4)))
      equation
        true = BackendVariable.isStringParam(var);
      then
        ((var,(s1,s2 + 1,s3,s4)));
    case ((var,(s1,s2,s3,s4)))
      equation
        true = BackendVariable.isParam(var);
      then
        ((var,(s1 + 1,s2,s3,s4)));
    case _ then inTpl;
  end matchcontinue;
end calculateParamSizes;

protected function calculateVarSizes "function: calculateVarSizes
  author: PA
  Helper function to calculateSizes"
  input tuple<Var, tuple<Integer,Integer,Integer,Integer,Integer>> inTpl;
  output tuple<Var, tuple<Integer,Integer,Integer,Integer,Integer>> outTpl;
algorithm
  outTpl :=
  matchcontinue (inTpl)      
    local
      Integer nx,ny,ny_string, ny_int, ny_bool;
      Var var;

    case ((var as BackendDAE.VAR(varKind = BackendDAE.VARIABLE(),varType=DAE.T_STRING(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string+1, ny_int,ny_bool)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.VARIABLE(),varType=DAE.T_INTEGER(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int+1,ny_bool)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.VARIABLE(),varType=DAE.T_BOOL(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int,ny_bool+1)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.VARIABLE()),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny+1,ny_string, ny_int,ny_bool)));
    
     case ((var as BackendDAE.VAR(varKind = BackendDAE.DISCRETE(),varType=DAE.T_STRING(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string+1, ny_int,ny_bool)));
        
     case ((var as BackendDAE.VAR(varKind = BackendDAE.DISCRETE(),varType=DAE.T_INTEGER(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int+1,ny_bool)));
     
     case ((var as BackendDAE.VAR(varKind = BackendDAE.DISCRETE(),varType=DAE.T_BOOL(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int,ny_bool+1)));
                 
     case ((var as BackendDAE.VAR(varKind = BackendDAE.DISCRETE()),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny+1,ny_string, ny_int,ny_bool)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.STATE()),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx+1,ny,ny_string, ny_int,ny_bool)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE(),varType=DAE.T_STRING(source = _)),(nx,ny,ny_string, ny_int, ny_bool))) /* A dummy state is an algebraic variable */
      then
        ((var,(nx,ny,ny_string+1, ny_int,ny_bool)));
        
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE(),varType=DAE.T_INTEGER(source = _)),(nx,ny,ny_string, ny_int, ny_bool))) /* A dummy state is an algebraic variable */
      then
        ((var,(nx,ny,ny_string, ny_int+1,ny_bool)));
    
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE(),varType=DAE.T_BOOL(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int,ny_bool+1)));
        
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE()),(nx,ny,ny_string, ny_int, ny_bool))) /* A dummy state is an algebraic variable */
      then
        ((var,(nx,ny+1,ny_string, ny_int,ny_bool)));

    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER(),varType=DAE.T_STRING(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string+1, ny_int,ny_bool)));
        
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER(),varType=DAE.T_INTEGER(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int+1,ny_bool)));
    
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER(),varType=DAE.T_BOOL(source = _)),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny,ny_string, ny_int,ny_bool+1)));
        
    case ((var as BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER()),(nx,ny,ny_string, ny_int, ny_bool)))
      then
        ((var,(nx,ny+1,ny_string, ny_int,ny_bool)));

    case _ then inTpl;
  end matchcontinue;
end calculateVarSizes;

protected function calculateValues "function: calculateValues
  author: PA
  This function calculates the values from the parameter binding expressions.
  modefication: wbraun 
  Use really only parameter bindungs for evaluation."
  input BackendDAE.BackendDAE inBackendDAE;
  output BackendDAE.BackendDAE outBackendDAE;
algorithm
  outBackendDAE := match (inBackendDAE)
    local
      list<Var> knvarlst,varlst1,varlst2;
      BackendDAE.Variables knvars,extVars,paramvars,av;
      EquationArray seqns,ie;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcs;
      BackendDAE.EventInfo wc;
      ExternalObjectClasses extObjCls;
      EqSystems eqs;
      BackendDAEType btp;
      BackendDAE.SymbolicJacobians symjacs;
    case (BackendDAE.DAE(eqs,BackendDAE.SHARED(knownVars = knvars,externalObjects=extVars,aliasVars = av,
                 initialEqs = ie,removedEqs = seqns, constraints = constrs,classAttrs = clsAttrs, cache=cache,env=env, functionTree = funcs, eventInfo = wc, extObjClasses=extObjCls, backendDAEType=btp, symjacs=symjacs)))
      equation
        knvarlst = varList(knvars);
        (varlst1,varlst2) = List.splitOnTrue(knvarlst,BackendVariable.isParam);
        paramvars = listVar(varlst1);
        knvarlst = List.map3(varlst1, calculateValue, cache, env, paramvars);
        knvars = listVar(listAppend(knvarlst,varlst2));
      then
        BackendDAE.DAE(eqs,BackendDAE.SHARED(knvars,extVars,av,ie,seqns,constrs,clsAttrs,cache,env,funcs,wc,extObjCls,btp,symjacs));
  end match;
end calculateValues;

protected function calculateValue
  input Var inVar;
  input Env.Cache cache;
  input Env.Env env;
  input BackendDAE.Variables vars;
  output Var outVar;
algorithm
  outVar := matchcontinue(inVar, cache, env, vars)
    local
      Var var;
      DAE.ComponentRef cr;
      VarKind vk;
      DAE.VarDirection vd;
      DAE.VarParallelism prl;
      BackendDAE.Type ty;
      DAE.Exp e;
      DAE.InstDims dims;
      DAE.ElementSource src;
      Option<DAE.VariableAttributes> va;
      Option<SCode.Comment> c;
      DAE.ConnectorType ct;
      Values.Value v;
    case (var as BackendDAE.VAR(bindValue = SOME(_)), _, _, _)
      equation
        print("*** Not Ceval.eval var: ");
        BackendDump.dumpVars({var});
        print("\n");
      then
        var;      
    case (BackendDAE.VAR(varName = cr, varKind = vk, varDirection = vd, varParallelism = prl,
          varType = ty, bindExp = SOME(e), arryDim = dims, source = src, 
          values = va, comment = c, connectorType = ct), _, _, _)
      equation
        // wbraun: Evaluate parameter expressions only if they are
        //         constant at compile time otherwise we solve them 
        //         much faster at runtime. 
        //((e, _)) = Expression.traverseExp(e, replaceCrefsWithValues, (vars, cr_orign));  
        true = Expression.isConst(e);
        (_, v, _) = Ceval.ceval(cache, env, e, false, NONE(), Ceval.NO_MSG());
      then
        BackendDAE.VAR(cr, vk, vd, prl, ty, SOME(e), SOME(v), dims, src, va, c, ct);        
    else inVar;
  end matchcontinue;
end calculateValue;

public function replaceCrefsWithValues
  input tuple<DAE.Exp, tuple<BackendDAE.Variables, DAE.ComponentRef>> inTuple;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables, DAE.ComponentRef>> outTuple;
algorithm
  outTuple := matchcontinue(inTuple)
    local
      DAE.Exp e;
      BackendDAE.Variables vars;
      DAE.ComponentRef cr, cr_orign;
    case ((DAE.CREF(cr, _), (vars, cr_orign)))
      equation
          false = ComponentReference.crefEqualNoStringCompare(cr, cr_orign);
         ({BackendDAE.VAR(bindExp = SOME(e))}, _) = BackendVariable.getVar(cr, vars);
         ((e, _)) = Expression.traverseExp(e, replaceCrefsWithValues, (vars, cr_orign));
      then
        ((e, (vars,cr_orign)));
    case (_) then inTuple;
  end matchcontinue;
end replaceCrefsWithValues;
  
public function makeExpType
"Transforms a BackendDAE.Type to DAE.Type"
  input BackendDAE.Type inType;
  output DAE.Type outType;
algorithm
  outType := inType;
end makeExpType;

public function emptyVars
"function: emptyVars
  author: PA
  Returns a Variable datastructure that is empty.
  Using the bucketsize 10000 and array size 1000."
  output BackendDAE.Variables outVariables;
protected
  array<list<BackendDAE.CrefIndex>> arr;
  list<Option<Var>> lst;
  array<Option<Var>> emptyarr;
  Integer bucketSize, arrSize;
algorithm
  bucketSize := BaseHashTable.bigBucketSize;
  arrSize := bucketSize; // BaseHashTable.bucketToValuesSize(bucketSize);
  arr := arrayCreate(bucketSize, {});
  emptyarr := arrayCreate(arrSize, NONE());
  outVariables := BackendDAE.VARIABLES(arr,BackendDAE.VARIABLE_ARRAY(0,arrSize,emptyarr),bucketSize,0);
end emptyVars;

public function addAliasVariables
"function: addAliasVariables
  author: Frenkel TUD 2010-12
  Add an alias variable to the AliasVariables "
  input list<Var> inVars;
  input BackendDAE.Variables inAliasVariables;
  output BackendDAE.Variables outAliasVariables;
algorithm
algorithm
  outAliasVariables := matchcontinue (inVars,inAliasVariables)
    local
      BackendDAE.Variables aliasVariables;
      DAE.ComponentRef cr;
      DAE.Exp exp;
      Var v;
      list<Var> rest;
    case ({},_) then inAliasVariables;
    case (v::rest,_)
      equation
        aliasVariables = BackendVariable.addVar(v,inAliasVariables);
        exp = BackendVariable.varBindExp(v);
        cr = BackendVariable.varCref(v);
        Debug.fcall(Flags.DEBUG_ALIAS,BackendDump.debugStrCrefStrExpStr,("++++ added Alias eqn: ",cr," = ",exp,"\n"));
      then
       addAliasVariables(rest,aliasVariables);
    case (_,_)
      equation
        print("- BackendDAEUtil.addAliasVariables failed\n");
      then
        fail();
  end matchcontinue;
end addAliasVariables;

public function equationList "function: equationList
  author: PA
  Transform the expandable BackendDAE.Equation array to a list of Equations."
  input EquationArray inEquationArray;
  output list<BackendDAE.Equation> outEquationLst;
algorithm
  outEquationLst := matchcontinue (inEquationArray)
    local
      array<Option<BackendDAE.Equation>> arr;
      BackendDAE.Equation elt;
      Integer n,size;
      list<BackendDAE.Equation> lst;
    
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = 0,equOptArr = arr)) then {};
    
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = 1,equOptArr = arr))
      equation
        SOME(elt) = arr[1];
      then
        {elt};
    
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = n,arrSize = size,equOptArr = arr))
      equation
        lst = equationList2(arr, n, {});
      then
        lst;
    
    case (_)
      equation
        print("- BackendDAEUtil.equationList failed\n");
      then
        fail();
  end matchcontinue;
end equationList;

protected function equationList2 "function: equationList2
  author: PA
  Helper function to equationList
  inputs:  (Equation option array, int /* pos */, int /* lastpos */)
  outputs: BackendDAE.Equation list"
  input array<Option<BackendDAE.Equation>> arr;
  input Integer pos;
  input list<BackendDAE.Equation> iAcc;
  output list<BackendDAE.Equation> outEquationLst;
algorithm
  outEquationLst := matchcontinue (arr,pos,iAcc)
    local
      BackendDAE.Equation e;
    case (_,0,_) then iAcc;    
    case (_,_,_)
      equation
        SOME(e) = arr[pos];
      then
        equationList2(arr,pos-1,e::iAcc);
    case (_,_,_)
      then
        equationList2(arr,pos-1,iAcc);
  end matchcontinue;
end equationList2;

public function listEquation "function: listEquation
  author: PA
  Transform the a list of Equations into an expandable BackendDAE.Equation array."
  input list<BackendDAE.Equation> lst;
  output EquationArray outEquationArray;
protected
  Integer len,size,arrsize;
  Real rlen,rlen_1;
  array<Option<BackendDAE.Equation>> optarr,eqnarr,newarr;
  list<Option<BackendDAE.Equation>> eqn_optlst;
algorithm
  len := listLength(lst);
  rlen := intReal(len);
  rlen_1 := rlen *. 1.4;
  arrsize := realInt(rlen_1);
  optarr := arrayCreate(arrsize, NONE());
  eqn_optlst := List.map(lst, Util.makeOption);
  eqnarr := listArray(eqn_optlst);
  newarr := Util.arrayCopy(eqnarr, optarr);
  size := BackendEquation.equationLstSize(lst);
  outEquationArray := BackendDAE.EQUATION_ARRAY(size,len,arrsize,newarr);
end listEquation;

public function varList
"function: varList
  Takes BackendDAE.Variables and returns a list of \'Var\', useful for e.g. dumping."
  input BackendDAE.Variables inVariables;
  output list<Var> outVarLst;
algorithm
  outVarLst := match (inVariables)
    local
      list<Var> varlst;
      VariableArray vararr;
    
    case (BackendDAE.VARIABLES(varArr = vararr))
      equation
        varlst = vararrayList(vararr);
      then
        varlst;
  end match;
end varList;

public function listVar
"function: listVar
  author: PA
  Takes Var list and creates a BackendDAE.Variables structure, see also var_list."
  input list<Var> inVarLst;
  output BackendDAE.Variables outVariables;
algorithm
  outVariables := match (inVarLst)
    local
      BackendDAE.Variables res,vars;
      Var v;
      list<Var> vs;
    
    case ({})
      equation
        res = emptyVars();
      then
        res;
    
    case ((v :: vs))
      equation
        vars = listVar(vs);
      then
        BackendVariable.addVar(v, vars);
  end match;
end listVar;

public function listVar1
"function: listVar
  author: Frenkel TUD 2012-05
  ToDo: replace all listVar calls with this function, tailrecursive implementation
  Takes BackendDAE.Var list and creates a BackendDAE.Variables structure, see also var_list."
  input list<BackendDAE.Var> inVarLst;
  output BackendDAE.Variables outVariables;
algorithm
  outVariables := List.fold(inVarLst,BackendVariable.addVar,emptyVars());
end listVar1;

protected function vararrayList
"function: vararrayList
  Transforms a VariableArray to a Var list"
  input VariableArray inVariableArray;
  output list<Var> outVarLst;
algorithm
  outVarLst:=
  matchcontinue (inVariableArray)
    local
      array<Option<Var>> arr;
      Var elt;
      Integer n,size;
    case (BackendDAE.VARIABLE_ARRAY(numberOfElements = 0,varOptArr = arr)) then {};
    case (BackendDAE.VARIABLE_ARRAY(numberOfElements = 1,varOptArr = arr))
      equation
        SOME(elt) = arr[1];
      then
        {elt};
    case (BackendDAE.VARIABLE_ARRAY(numberOfElements = n,arrSize = size,varOptArr = arr))
      then
        vararrayList2(arr, n, {});
  end matchcontinue;
end vararrayList;

protected function vararrayList2
"function: vararrayList2
  Helper function to vararrayList"
  input array<Option<Var>> arr;
  input Integer pos;
  input list<Var> inVarLst;
  output list<Var> outVarLst;
algorithm
  outVarLst:=
  matchcontinue (arr,pos,inVarLst)
    local
      Var v;
      list<Var> res;
    case (_,0,_) then inVarLst;
    case (_,_,_)
      equation
        SOME(v) = arr[pos];
      then
        vararrayList2(arr,pos-1,v::inVarLst);
    case (_,_,_)
      then
        vararrayList2(arr,pos-1,inVarLst);
  end matchcontinue;
end vararrayList2;

public function isDiscreteEquation
  input BackendDAE.Equation eqn;
  input BackendDAE.Variables vars;
  input BackendDAE.Variables knvars;
  output Boolean b;
algorithm
  b := matchcontinue(eqn,vars,knvars)
    local 
      DAE.Exp e1,e2; 
      DAE.ComponentRef cr; 
      list<DAE.Exp> expl;
      list<DAE.Statement> stmts;
    
    case(BackendDAE.EQUATION(exp = e1,scalar = e2),vars,knvars) equation
      b = boolAnd(isDiscreteExp(e1,vars,knvars), isDiscreteExp(e2,vars,knvars));
    then b;
    case(BackendDAE.COMPLEX_EQUATION(left = e1,right = e2),vars,knvars) equation
      b = boolAnd(isDiscreteExp(e1,vars,knvars), isDiscreteExp(e2,vars,knvars));
    then b;    
    case(BackendDAE.ARRAY_EQUATION(left = e1,right = e2),vars,knvars) equation
      b = boolAnd(isDiscreteExp(e1,vars,knvars), isDiscreteExp(e2,vars,knvars));
    then b;    
    case(BackendDAE.SOLVED_EQUATION(componentRef = cr,exp = e2),vars,knvars) equation
      e1 = Expression.crefExp(cr);
      b = boolAnd(isDiscreteExp(e1,vars,knvars), isDiscreteExp(e2,vars,knvars));
    then b;
    case(BackendDAE.RESIDUAL_EQUATION(exp = e1),vars,knvars) equation
      b = isDiscreteExp(e1,vars,knvars);
    then b;
    case(BackendDAE.ALGORITHM(alg = DAE.ALGORITHM_STMTS(stmts)),vars,knvars) equation
      (_,(_,_,true)) = DAEUtil.traverseDAEEquationsStmts(stmts, isDiscreteExp1, (vars,knvars,false));
    then true;
    case(BackendDAE.WHEN_EQUATION(whenEquation = _),vars,knvars) then true;
    // returns false otherwise!
    case(_,_,_) then false;
  end matchcontinue;
end isDiscreteEquation;

public function isDiscreteExp "function: isDiscreteExp
 Returns true if expression is a discrete expression."
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  input BackendDAE.Variables knvars;
  output Boolean outBoolean;
algorithm
  outBoolean := 
  match(inExp,inVariables,knvars)
    local 
      Boolean b;
      Option<Boolean> obool;
  case(_,_,_)
    equation
      ((_,(_,_,obool))) = Expression.traverseExpTopDown(inExp, traversingisDiscreteExpFinder, (inVariables,knvars,NONE()));
      b = Util.getOptionOrDefault(obool,false);
      then
        b;
  end match;
end isDiscreteExp;

protected function isDiscreteExp1 "function: isDiscreteExp1
 Returns true if expression is a discrete expression."
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,BackendDAE.Variables,Boolean>> inExp;
  output tuple<DAE.Exp,tuple<BackendDAE.Variables,BackendDAE.Variables,Boolean>> outExp;
algorithm
  outExp := 
  match(inExp)
    local 
      Boolean b,b1;
      Option<Boolean> obool;
      DAE.Exp e;
      BackendDAE.Variables v,kv;
  case((e,(v,kv,true)))
     then inExp;
  case((e,(v,kv,b)))
    equation
      ((_,(_,_,obool))) = Expression.traverseExpTopDown(e, traversingisDiscreteExpFinder, (v,kv,NONE()));
      b1 = Util.getOptionOrDefault(obool,false);
      then
        ((e,(v,kv,b or b1)));
  end match;
end isDiscreteExp1;

protected function traversingisDiscreteExpFinder "
Author: Frenkel TUD 2010-11
Helper for isDiscreteExp"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,BackendDAE.Variables,Option<Boolean>>> inTpl;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,BackendDAE.Variables,Option<Boolean>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      BackendDAE.Variables vars,knvars;
      DAE.ComponentRef cr;
      VarKind kind;
      DAE.Exp e,e1,e2;
      Option<Boolean> blst;
      Boolean b,b1,b2;
      Boolean res;
      Var backendVar;

    case (((e as DAE.ICONST(integer = _),(vars,knvars,blst))))
      equation
        b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.RCONST(real = _),(vars,knvars,blst))))
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.SCONST(string = _),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.BCONST(bool = _),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.ENUM_LITERAL(name = _),(vars,knvars,blst))))
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CREF(componentRef = cr),(vars,knvars,blst))))
      equation
        ((BackendDAE.VAR(varKind = kind) :: _),_) = BackendVariable.getVar(cr, vars);
        res = isKindDiscrete(kind);
      then
        ((e,false,(vars,knvars,SOME(res))));
    // builtin variable time is not discrete
    case (((e as DAE.CREF(componentRef = DAE.CREF_IDENT("time",_,_)),(vars,knvars,blst)))) then ((e,false,(vars,knvars,SOME(false))));
    // Known variables that are input are continuous
    case (((e as DAE.CREF(componentRef = cr),(vars,knvars,blst))))
      equation
        (backendVar::_,_) = BackendVariable.getVar(cr,knvars);
        true = BackendVariable.isInput(backendVar);
      then
        ((e,false,(vars,knvars,SOME(false))));

    // parameters & constants
    // are always discrete
    case (((e as DAE.CREF(componentRef = cr),(vars,knvars,blst))))
      equation
        ((BackendDAE.VAR(varKind = kind) :: _),_) = BackendVariable.getVar(cr, knvars);
        b = Util.getOptionOrDefault(blst,true);
      then
        ((e,false,(vars,knvars,SOME(b))));
    
    case (((e as DAE.RELATION(exp1 = e1, exp2 = e2),(vars,knvars,blst)))) 
      equation
       b1 = isDiscreteExp(e1,vars,knvars);
       b2 = isDiscreteExp(e2,vars,knvars);
       b = Util.boolAndList({b1,b2});
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "pre")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "edge")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "change")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "ceil")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "floor")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "div")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "mod")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "rem")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
/*
    This cases are wrong because of Modelica Specification:
    
    3.8.3 
    
    Unless inside noEvent: Ordered relations (>,<,>=,<=) and the functions ceil, floor, div, mod,
    rem, abs, sign. These will generate events if at least one subexpression is not a
    discrete-time expression. [In other words, relations inside noEvent(), such as noEvent(x>1),
    are not discrete-time expressions].
    
    and 
    
    3.7.1
    
    abs(v): Is expanded into 
      noEvent(if v >= 0 then v else -v)
    Argument v needs to be an Integer or Real expression.
    sign(v): Is expanded into 
      noEvent(if v>0 then 1 else if v<0 then -1 else 0)
     Argument v needs to be an Integer or Real expression.

    case (((e as DAE.CALL(path = Absyn.IDENT(name = "abs")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "sign")),(vars,knvars,blst)))) 
      equation
       b = Util.getOptionOrDefault(blst,true);
      then ((e,false,(vars,knvars,SOME(b))));
*/
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "noEvent")),(vars,knvars,blst)))) then ((e,false,(vars,knvars,SOME(false))));

    case((e,(vars,knvars,NONE()))) then ((e,true,(vars,knvars,NONE())));
    case((e,(vars,knvars,SOME(b)))) then ((e,b,(vars,knvars,SOME(b))));
  end matchcontinue;
end traversingisDiscreteExpFinder;


public function isVarDiscrete "returns true if variable is discrete"
  input Var var;
  output Boolean res;
algorithm
  res := match(var)
    local VarKind kind;
    case(BackendDAE.VAR(varKind=kind)) then isKindDiscrete(kind);
  end match;
end isVarDiscrete;

protected function isKindDiscrete "function: isKindDiscrete
  Returns true if VarKind is discrete."
  input VarKind inVarKind;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inVarKind)
    case (BackendDAE.DISCRETE()) then true;
    case (BackendDAE.PARAM()) then true;
    case (BackendDAE.CONST()) then true;
    case (_) then false;
  end matchcontinue;
end isKindDiscrete;

public function statesAndVarsExp
"function: statesAndVarsExp
  This function investigates an expression and returns as subexpressions
  that are variable names or derivatives of state names or states
  inputs:  (DAE.Exp, BackendDAE.Variables)
  outputs: DAE.Exp list"
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  output list<DAE.Exp> outExpExpLst;
algorithm
  outExpExpLst := 
  match(inExp,inVariables)
    local list<DAE.Exp> exps;
  case(inExp,inVariables)
    equation
      ((_,(_,exps))) = Expression.traverseExpTopDown(inExp, traversingstatesAndVarsExpFinder, (inVariables,{}));
      then
        exps;
  end match;
end statesAndVarsExp;

public function traversingstatesAndVarsExpFinder "
Author: Frenkel TUD 2010-10
Helper for statesAndVarsExp"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<DAE.Exp>>> inTpl;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,list<DAE.Exp>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local
    DAE.ComponentRef cr;
    list<DAE.Exp> expl,res,creexps;
    DAE.Exp e,e1;
    list<DAE.Var> varLst;
    BackendDAE.Variables vars;
    // Special Case for Records 
    case (((e as DAE.CREF(componentRef = cr,ty= DAE.T_COMPLEX(varLst=varLst,complexClassType=ClassInf.RECORD(_)))),(vars,expl)))
      equation
        creexps = List.map1(varLst,Expression.generateCrefsExpFromExpVar,cr);
        ((_,(_,res))) = Expression.traverseExpListTopDown(creexps, traversingstatesAndVarsExpFinder, (vars,expl));
      then
        ((e,true,(vars,res)));
    // Special Case for unextended arrays
    case (((e as DAE.CREF(componentRef = cr,ty = DAE.T_ARRAY(dims=_))),(vars,expl)))
      equation
        ((e1,(_,true))) = extendArrExp((e,(NONE(),false)));
        ((_,(_,res))) = Expression.traverseExpTopDown(e1, traversingstatesAndVarsExpFinder, (vars,expl));
      then
        ((e,true,(vars,res)));
    // Special Case for time variable
    //case (((e as DAE.CREF(componentRef = DAE.CREF_IDENT(ident="time"))),(vars,expl)))  
    //  then ((e,false,(vars,e::expl)));        
    case (((e as DAE.CREF(componentRef = cr)),(vars,expl)))
      equation
        (_,_) = BackendVariable.getVar(cr, vars);
      then
        ((e,false,(vars,e::expl)));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)})),(vars,expl)))
      equation
        ((BackendDAE.VAR(varKind = BackendDAE.STATE()) :: _),_) = BackendVariable.getVar(cr, vars);
      then
        ((e,false,(vars,e::expl)));
    // is this case right?    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,expl))))
      equation
        (_,_) = BackendVariable.getVar(cr, vars);
      then
        ((e,false,(vars,expl)));
  case((e,(vars,expl))) then ((e,true,(vars,expl)));
end matchcontinue;
end traversingstatesAndVarsExpFinder;

public function isLoopDependent
  "Checks if an expression is a variable that depends on a loop iterator,
  ie. for i loop
        V[i] = ...  // V depends on i
      end for;
  Used by lowerStatementInputsOutputs in STMT_FOR case."
  input DAE.Exp varExp;
  input DAE.Exp iteratorExp;
  output Boolean isDependent;
algorithm
  isDependent := matchcontinue(varExp, iteratorExp)
    local
      list<DAE.Exp> subscript_exprs;
      list<DAE.Subscript> subscripts;
      DAE.ComponentRef cr;
    case (DAE.CREF(componentRef = cr), _)
      equation
        subscripts = ComponentReference.crefSubs(cr);
        subscript_exprs = List.map(subscripts, Expression.subscriptIndexExp);
        true = isLoopDependentHelper(subscript_exprs, iteratorExp);
      then true;
    case (DAE.ASUB(sub = subscript_exprs), _)
      equation
        true = isLoopDependentHelper(subscript_exprs, iteratorExp);
      then true;
    case (_,_)
      then false;
  end matchcontinue;
end isLoopDependent;

protected function isLoopDependentHelper
  "Helper for isLoopDependent.
  Checks if a list of subscripts contains a certain iterator expression."
  input list<DAE.Exp> subscripts;
  input DAE.Exp iteratorExp;
  output Boolean isDependent;
algorithm
  isDependent := matchcontinue(subscripts, iteratorExp)
    local
      DAE.Exp subscript;
      list<DAE.Exp> rest;
    case ({}, _) then false;
    case (subscript :: rest, _)
      equation
        true = Expression.expContains(subscript, iteratorExp);
      then true;
    case (subscript :: rest, _)
      equation
        true = isLoopDependentHelper(rest, iteratorExp);
      then true;
    case (_, _) then false;
  end matchcontinue;
end isLoopDependentHelper;

public function devectorizeArrayVar
  input DAE.Exp arrayVar;
  output DAE.Exp newArrayVar;
algorithm
  newArrayVar := matchcontinue(arrayVar)
    local 
      DAE.ComponentRef cr;
      DAE.Type ty;
      list<DAE.Exp> subs;
      DAE.Exp e;
      
    case (DAE.ASUB(exp = DAE.ARRAY(array = (DAE.CREF(componentRef = cr, ty = ty) :: _)), sub = subs))
      equation
        cr = ComponentReference.crefStripLastSubs(cr);
        e = Expression.crefExp(cr);
      then
        // adrpo: TODO! FIXME! check if this is TYPE correct!
        //        shouldn't we change the type using the subs?
        Expression.makeASUB(e, subs);
    
    case (DAE.ASUB(exp = DAE.MATRIX(matrix = (((DAE.CREF(componentRef = cr, ty = ty)) :: _) :: _)), sub = subs))
      equation
        cr = ComponentReference.crefStripLastSubs(cr);
        e = Expression.crefExp(cr);
      then
        // adrpo: TODO! FIXME! check if this is TYPE correct!
        //        shouldn't we change the type using the subs?
        Expression.makeASUB(e, subs);
    
    case (_) then arrayVar;
  end matchcontinue;
end devectorizeArrayVar;

public function explodeArrayVars
  "Explodes an array variable into its elements. Takes a variable that is a CREF
  or ASUB, the name of the iterator variable and a range expression that the
  iterator iterates over."
  input DAE.Exp arrayVar;
  input DAE.Exp iteratorExp;
  input DAE.Exp rangeExpr;
  input BackendDAE.Variables vars;
  output list<DAE.Exp> arrayElements;
algorithm
  arrayElements := matchcontinue(arrayVar, iteratorExp, rangeExpr, vars)
    local
      list<DAE.Exp> clonedElements, newElements;
      list<DAE.Exp> indices;
      DAE.ComponentRef cref;
      list<DAE.ComponentRef> varCrefs;
      list<DAE.Exp> varExprs;
      DAE.Exp daeExp;
      list<Var> bvars;
    
    case (DAE.CREF(componentRef = _), _, _, _)
      equation
        indices = rangeIntExprs(rangeExpr);
        clonedElements = List.fill(arrayVar, listLength(indices));
        newElements = generateArrayElements(clonedElements, indices, iteratorExp);
      then newElements;
        
    case (DAE.ASUB(exp = DAE.CREF(componentRef = _)), _, _, _)
      equation
        // If the range is constant, then we can use it to generate only those
        // array elements that are actually used.
        indices = rangeIntExprs(rangeExpr);
        clonedElements = List.fill(arrayVar, listLength(indices));
        newElements = generateArrayElements(clonedElements, indices, iteratorExp);
      then newElements;
        
    case (DAE.CREF(componentRef = cref), _, _, _)
      equation
        (bvars, _) = BackendVariable.getVar(cref, vars);
        varCrefs = List.map(bvars, BackendVariable.varCref);
        varExprs = List.map(varCrefs, Expression.crefExp);
      then varExprs;

    case (DAE.ASUB(exp = DAE.CREF(componentRef = cref)), _, _, _)
      equation
        // If the range is not constant, then we just extract all array elements
        // of the array.
        (bvars, _) = BackendVariable.getVar(cref, vars);
        varCrefs = List.map(bvars, BackendVariable.varCref);
        varExprs = List.map(varCrefs, Expression.crefExp);
      then varExprs;
      
    case (DAE.ASUB(exp = daeExp), _, _, _)
      equation
        varExprs = Expression.flattenArrayExpToList(daeExp);
      then
        varExprs;
  end matchcontinue;
end explodeArrayVars;

protected function rangeIntExprs
  "Tries to convert a range to a list of integer expressions. Returns a list of
  integer expressions if possible, or fails. Used by explodeArrayVars."
  input DAE.Exp range;
  output list<DAE.Exp> integers;
algorithm
  integers := match(range)
    local
      list<DAE.Exp> arrayElements;
      Integer start, stop;
      list<Integer> vals;
    
    case (DAE.ARRAY(array = arrayElements)) then arrayElements;
    
    case (DAE.RANGE(start = DAE.ICONST(integer = start), stop = DAE.ICONST(integer = stop), step = NONE()))
      equation
        vals = ExpressionSimplify.simplifyRange(start, 1, stop);
        arrayElements = List.map(vals, Expression.makeIntegerExp);
      then
        arrayElements;
    
    case (_) then fail();
    
  end match;
end rangeIntExprs;

public function equationNth "function: equationNth
  author: PA

  Return the n:th equation from the expandable equation array
  indexed from 0..1.

  inputs:  (EquationArray, int /* n */)
  outputs:  Equation

"
  input EquationArray inEquationArray;
  input Integer inInteger;
  output BackendDAE.Equation outEquation;
algorithm
  outEquation:=
  matchcontinue (inEquationArray,inInteger)
    local
      BackendDAE.Equation e;
      Integer n,pos;
      array<Option<BackendDAE.Equation>> arr;
      String str;
      
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = n,equOptArr = arr),pos)
      equation
        (pos < n) = true;
        SOME(e) = arr[pos + 1];
      then
        e;
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = n),pos)
      equation
        str = "BackendDAEUtil.equationNth failed; numberOfElement=" +& intString(n) +& "; pos=" +& intString(pos);
        print(str +& "\n");
        Error.addMessage(Error.INTERNAL_ERROR,{str});
      then
        fail();

  end matchcontinue;
end equationNth;

public function systemSize 
"function: equationSize
  author: Frenkel TUD
  Returns the size of the dae system, the size of the equations in an EquationArray,
  which not corresponds to the number of equations in a system."
  input BackendDAE.EqSystem syst;
  output Integer n;
algorithm
  n := match(syst)
    local
      EquationArray eqns;
    case BackendDAE.EQSYSTEM(orderedEqs = eqns)
      equation
        n = equationSize(eqns);
      then n;
  end match;
end systemSize;

public function equationSize "function: equationSize
  author: PA

  Returns the size of the equations in an EquationArray, which not 
  corresponds to the number of equations in a system."
  input EquationArray inEquationArray;
  output Integer outInteger;
algorithm
  outInteger:=
  match (inEquationArray)
    local Integer n;
    case (BackendDAE.EQUATION_ARRAY(size = n)) then n;
  end match;
end equationSize;

public function equationArraySizeDAE 
"function: equationArraySizeDAE
  author: Frenkel TUD
  Returns the number of equations in a system."
  input BackendDAE.EqSystem dae;
  output Integer n;
algorithm
  n := match(dae)
    local
      EquationArray eqns;
    case BackendDAE.EQSYSTEM(orderedEqs = eqns)
      equation
        n = equationArraySize(eqns);
      then n;
  end match;
end equationArraySizeDAE;

public function equationArraySize "function: equationArraySize
  author: PA

  Returns the number of equations in an EquationArray, which not 
  corresponds to the number of equations in a system but not
  to the size of the system"
  input EquationArray inEquationArray;
  output Integer outInteger;
algorithm
  outInteger:=
  match (inEquationArray)
    local Integer n;
    case (BackendDAE.EQUATION_ARRAY(numberOfElement = n)) then n;
  end match;
end equationArraySize;

protected function generateArrayElements
  "Takes a list of identical CREF or ASUB expressions, a list of ICONST indices
  and a loop iterator expression, and recursively replaces the loop iterator
  with a constant index. Ex:
    generateArrayElements(cref[i,j], {1,2,3}, j) =>
      {cref[i,1], cref[i,2], cref[i,3]}"
  input list<DAE.Exp> clones;
  input list<DAE.Exp> indices;
  input DAE.Exp iteratorExp;
  output list<DAE.Exp> newElements;
algorithm
  newElements := match(clones, indices, iteratorExp)
    local
      DAE.Exp clone, newElement, newElement2, index;
      list<DAE.Exp> restClones, restIndices, elements;
    case ({}, {}, _) then {};
    case (clone :: restClones, index :: restIndices, _)
      equation
        ((newElement, _)) = Expression.replaceExp(clone, iteratorExp, index);
        newElement2 = simplifySubscripts(newElement);
        elements = generateArrayElements(restClones, restIndices, iteratorExp);
      then (newElement2 :: elements);
  end match;
end generateArrayElements;

protected function simplifySubscripts
  "Tries to simplify the subscripts of a CREF or ASUB. If an ASUB only contains
  constant subscripts, such as cref[1,4], then it also needs to be converted to
  a CREF."
  input DAE.Exp asub;
  output DAE.Exp maybeCref;
algorithm
  maybeCref := matchcontinue(asub)
    local
      DAE.Ident varIdent;
      DAE.Type arrayType, varType;
      list<DAE.Exp> subExprs, subExprsSimplified;
      list<DAE.Subscript> subscripts;
      DAE.Exp newCrefExp;
      DAE.ComponentRef cref_;

    // A CREF => just simplify the subscripts.
    case (DAE.CREF(DAE.CREF_IDENT(varIdent, arrayType, subscripts), varType))
      equation
        subscripts = List.map(subscripts, simplifySubscript);
        cref_ = ComponentReference.makeCrefIdent(varIdent, arrayType, subscripts);
        newCrefExp = Expression.makeCrefExp(cref_, varType);
      then 
        newCrefExp;
        
    // An ASUB => convert to CREF if only constant subscripts.
    case (DAE.ASUB(DAE.CREF(DAE.CREF_IDENT(varIdent, arrayType, _), varType), subExprs))
      equation
        {} = List.select(subExprs, Expression.isNotConst);
        // If a subscript is not a single constant value it needs to be
        // simplified, e.g. cref[3+4] => cref[7], otherwise some subscripts
        // might be counted twice, such as cref[3+4] and cref[2+5], even though
        // they reference the same element.
        subExprsSimplified = ExpressionSimplify.simplifyList(subExprs, {});
        subscripts = List.map(subExprsSimplified, Expression.makeIndexSubscript);
        cref_ = ComponentReference.makeCrefIdent(varIdent, arrayType, subscripts);
        newCrefExp = Expression.makeCrefExp(cref_, varType);
      then 
        newCrefExp;
        
    case (_) then asub;
  end matchcontinue;
end simplifySubscripts;

protected function simplifySubscript
  input DAE.Subscript sub;
  output DAE.Subscript simplifiedSub;
algorithm
  simplifiedSub := matchcontinue(sub)
    local
      DAE.Exp e;
    
    case (DAE.INDEX(exp = e))
      equation
        (e,_) = ExpressionSimplify.simplify(e);
      then 
        DAE.INDEX(e);
    
    case (_) then sub;
    
  end matchcontinue;
end simplifySubscript;


/*******************************************
   Functions that deals with BackendDAE as input
********************************************/

public function generateStatePartition "function:generateStatePartition

  This function traverses the equations to find out which blocks needs to
  be solved by the numerical solver (Dynamic Section) and which blocks only
  needs to be solved for output to file ( Accepted Section).
  This is done by traversing the graph of strong components, where
  equations/variable pairs correspond to nodes of the graph. The edges of
  this graph are the dependencies between blocks or components.
  The traversal is made in the backward direction of this graph.
  The result is a split of the blocks into two lists.
  inputs: (blocks: int list list,
             daeLow: BackendDAE,
             assignments1: int vector,
             assignments2: int vector,
             incidenceMatrix: IncidenceMatrix,
             incidenceMatrixT: IncidenceMatrixT)
  outputs: (dynamicBlocks: int list list, outputBlocks: int list list)
"
  input BackendDAE.EqSystem syst;
  output BackendDAE.StrongComponents outCompsStates;
  output BackendDAE.StrongComponents outCompsNoStates;  
algorithm
  (outCompsStates,outCompsNoStates):=
  matchcontinue syst
    local
      Integer size;
      array<Integer> arr,arr_1;
      BackendDAE.StrongComponents comps,blt_states,blt_no_states;
      BackendDAE.Variables v,kv;
      EquationArray e,se,ie;
      array<Integer> ass1,ass2;
      array<list<Integer>> m,mt;
    case (syst as BackendDAE.EQSYSTEM(matching=BackendDAE.MATCHING(ass1,ass2,comps)))
      equation
        size = arrayLength(ass1) "equation_size(e) => size &" ;
        arr = arrayCreate(size, 0);
        arr_1 = markStateEquations(syst, arr, ass1, ass2);
        (blt_states,blt_no_states) = splitBlocks(comps, arr_1);
      then
        (blt_states,blt_no_states);
    else
      equation
        print("- BackendDAEUtil.generateStatePartition failed\n");
      then
        fail();
  end matchcontinue;
end generateStatePartition;

protected function splitBlocks "function: splitBlocks
  Split the blocks into two parts, one dynamic and one output, depedning
  on if an equation in the block is marked or not.
  inputs:  (blocks: int list list, marks: int array)
  outputs: (dynamic: int list list, output: int list list)"
  input BackendDAE.StrongComponents inComps;
  input array<Integer> inIntegerArray;
  output BackendDAE.StrongComponents outCompsStates;
  output BackendDAE.StrongComponents outCompsNoStates;
algorithm
  (outCompsStates,outCompsNoStates) := matchcontinue (inComps,inIntegerArray)
    local
      BackendDAE.StrongComponents comps,states,output_;
      BackendDAE.StrongComponent comp;
      list<Integer> eqns;
      array<Integer> arr;
    
    case ({},_) then ({},{});
        
    case (comp::comps,arr)
      equation
        (eqns,_) = BackendDAETransform.getEquationAndSolvedVarIndxes(comp);
        true = blockIsDynamic(eqns, arr) "block is dynamic, belong in dynamic section" ;
        (states,output_) = splitBlocks(comps, arr);
      then
        ((comp :: states),output_);              
    
    case (comp :: comps,arr)
      equation
        (states,output_) = splitBlocks(comps, arr) "block is not dynamic, belong in output section" ;
      then
        (states,(comp :: output_));
    else
      equation
        print("- BackendDAEUtil.splitBlocks failed\n");
      then
        fail();        
  end matchcontinue;
end splitBlocks;

public function blockIsDynamic "function blockIsDynamic
  Return true if the block contains a variable that is marked"
  input list<Integer> inIntegerLst;
  input array<Integer> inIntegerArray;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inIntegerLst,inIntegerArray)
    local
      Integer x,mark_value;
      Boolean res;
      list<Integer> xs;
      array<Integer> arr;
    
    case ({},_) then false;
    
    case ((x :: xs),arr)
      equation
        0 = arr[x];
        res = blockIsDynamic(xs, arr);
      then
        res;
    
    case ((x :: xs),arr)
      equation
        mark_value = arr[x];
        (mark_value <> 0) = true;
      then
        true;
  end matchcontinue;
end blockIsDynamic;

public function markStateEquations "function: markStateEquations
  This function goes through all equations and marks the ones that
  calculates a state, or is needed in order to calculate a state,
  with a non-zero value in the array passed as argument.
  This is done by traversing the directed graph of nodes where
  a node is an equation/solved variable and following the edges in the
  backward direction.
  inputs: (daeLow: BackendDAE,
             marks: int array,
    incidenceMatrix: IncidenceMatrix,
    incidenceMatrixT: IncidenceMatrixT,
    assignments1: int vector,
    assignments2: int vector)
  outputs: marks: int array"
  input BackendDAE.EqSystem syst;
  input array<Integer> inIntegerArray2;
  input array<Integer> inIntegerArray5;
  input array<Integer> inIntegerArray6;
  output array<Integer> outIntegerArray;
algorithm
  outIntegerArray:=
  matchcontinue (syst,inIntegerArray2,inIntegerArray5,inIntegerArray6)
    local
      list<Integer> statevarindx_lst;
      array<Integer> arr_1,arr,a1,a2;
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      BackendDAE.Variables v;
    
    case (BackendDAE.EQSYSTEM(orderedVars = v,m=SOME(m),mT=SOME(mt)),arr,a1,a2)
      equation
        (_,statevarindx_lst) = BackendVariable.getAllStateVarIndexFromVariables(v);
        ((arr_1,_,_,_,_)) = List.fold(statevarindx_lst, markStateEquation, (arr,m,mt,a1,a2));
      then
        arr_1;
    
    else
      equation
        print("- BackendDAEUtil.markStateEquations failed\n");
      then
        fail();
  end matchcontinue;
end markStateEquations;
     
protected function markStateEquation
"function: markStateEquation
  This function is a helper function to mark_state_equations
  It performs marking for one equation and its transitive closure by
  following edges in backward direction.
  inputs and outputs are tuples so we can use Util.list_fold"
  input Integer inVarIndx;
  input tuple<array<Integer>, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT, array<Integer>, array<Integer>> inTpl;
  output tuple<array<Integer>, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT, array<Integer>, array<Integer>> outTpl;
algorithm
  outTpl:=
  matchcontinue (inVarIndx,inTpl)
    local
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      array<Integer> arr_1,arr,a1,a2;
      Integer eindx;
    
    case (_,(arr,m,mt,a1,a2))
      equation
        eindx = a1[inVarIndx];
        ((arr_1,m,mt,a1,a2)) = markStateEquation2({eindx}, (arr,m,mt,a1,a2));
      then
        ((arr_1,m,mt,a1,a2));
    
    case (_,(arr,m,mt,a1,a2))
      equation
        failure(_ = a1[inVarIndx]);
        print("-  BackendDAEUtil.markStateEquation index = " +& intString(inVarIndx) +& ", failed\n");
      then
        fail();
  end matchcontinue;
end markStateEquation;

protected function markStateEquation2
"function: markStateEquation2
  Helper function to mark_state_equation
  Does the job by looking at variable indexes and incidencematrices.
  inputs: (eqns: int list,
             marks: (int array  BackendDAE.IncidenceMatrix  BackendDAE.IncidenceMatrixT  int vector  int vector))
  outputs: ((marks: int array  BackendDAE.IncidenceMatrix  IncidenceMatrixT
        int vector  int vector))"
  input list<Integer> inIntegerLst;
  input tuple<array<Integer>, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT, array<Integer>, array<Integer>> inTplIntegerArrayIncidenceMatrixIncidenceMatrixTIntegerArrayIntegerArray;
  output tuple<array<Integer>, BackendDAE.IncidenceMatrix, BackendDAE.IncidenceMatrixT, array<Integer>, array<Integer>> outTplIntegerArrayIncidenceMatrixIncidenceMatrixTIntegerArrayIntegerArray;
algorithm
  outTplIntegerArrayIncidenceMatrixIncidenceMatrixTIntegerArrayIntegerArray:=
  matchcontinue (inIntegerLst,inTplIntegerArrayIncidenceMatrixIncidenceMatrixTIntegerArrayIntegerArray)
    local
      array<Integer> marks,marks_1,marks_2,marks_3;
      array<list<Integer>> m,mt,m_1,mt_1;
      array<Integer> a1,a2,a1_1,a2_1;
      Integer eqn,mark_value,len;
      list<Integer> inv_reachable,inv_reachable_1,eqns;
      list<list<Integer>> inv_reachable_2;
      String eqnstr,lens,ms;
    
    case ({},(marks,m,mt,a1,a2)) then ((marks,m,mt,a1,a2));
    
    case ((eqn :: eqns),(marks,m,mt,a1,a2))
      equation
        // "Mark an unmarked node/equation"
        0 = marks[eqn];
        marks_1 = arrayUpdate(marks, eqn, 1);
        inv_reachable = invReachableNodes(eqn, m, mt, a1, a2);
        inv_reachable_1 = removeNegative(inv_reachable);
        inv_reachable_2 = List.map(inv_reachable_1, List.create);
        ((marks_2,m,mt,a1,a2)) = List.fold(inv_reachable_2, markStateEquation2, (marks_1,m,mt,a1,a2));
        ((marks_3,m_1,mt_1,a1_1,a2_1)) = markStateEquation2(eqns, (marks_2,m,mt,a1,a2));
      then
        ((marks_3,m_1,mt_1,a1_1,a2_1));
    
    case ((eqn :: eqns),(marks,m,mt,a1,a2))
      equation
        // Node allready marked.
        mark_value = marks[eqn];
        (mark_value <> 0) = true;
        ((marks_1,m_1,mt_1,a1_1,a2_1)) = markStateEquation2(eqns, (marks,m,mt,a1,a2));
      then
        ((marks_1,m_1,mt_1,a1_1,a2_1));
    
    case ((eqn :: _),(marks,m,mt,a1,a2))
      equation
        print("- BackendDAEUtil.markStateEquation2 failed, eqn: ");
        eqnstr = intString(eqn);
        print(eqnstr);
        print("array length = ");
        len = arrayLength(marks);
        lens = intString(len);
        print(lens);
        print("\n");
        mark_value = marks[eqn];
        ms = intString(mark_value);
        print("mark_value: ");
        print(ms);
        print("\n");
      then
        fail();
  end matchcontinue;
end markStateEquation2;

public function invReachableNodes "function: invReachableNodes
  Similar to reachable_nodes, but follows edges in backward direction
  I.e. what equations/variables needs to be solved to solve this one."
  input Integer e;
  input BackendDAE.IncidenceMatrix m;
  input BackendDAE.IncidenceMatrixT mt;
  input array<Integer> a1;
  input array<Integer> a2;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst :=
  matchcontinue (e,m,mt,a1,a2)
    local
      list<Integer> var_lst,var_lst_1,lst;
      String eqn_str;
    
    case (_,_,_,_,_)
      equation
        var_lst = m[e];
        var_lst_1 = removeNegative(var_lst);
        lst = invReachableNodes2(var_lst_1, a1);
      then
        lst;
    
    case (_,_,_,_,_)
      equation
        print("- BackendDAEUtil.invEeachableNodes failed, eqn: ");
        eqn_str = intString(e);
        print(eqn_str);
        print("\n");
      then
        fail();
  end matchcontinue;
end invReachableNodes;

protected function invReachableNodes2 "function: invReachableNodes2
  Helper function to invReachableNodes
  inputs:  (variables: int list, assignments1: int vector)
  outputs: int list"
  input list<Integer> inIntegerLst;
  input array<Integer> inIntegerArray;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inIntegerLst,inIntegerArray)
    local
      list<Integer> eqns,vs;
      Integer eqn,v;
      array<Integer> a1;
    
    case ({},_) then {};
    
    case ((v :: vs),a1)
      equation
        eqns = invReachableNodes2(vs, a1);
        eqn = a1[v] "Which equation is variable solved in?" ;
      then
        (eqn :: eqns);
    
    case (_,_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"- BackendDAEUtil.invReachableNodes2 failed\n"});
      then
        fail();
  end matchcontinue;
end invReachableNodes2;

public function removeNegative
"function: removeNegative
  author: PA
  Removes all negative integers."
  input list<Integer> lst;
  output list<Integer> lst_1;
algorithm
  lst_1 := List.select(lst, Util.intPositive);
end removeNegative;

public function eqnsForVarWithStates
"function: eqnsForVarWithStates
  author: PA
  This function returns all equations as a list of equation indices
  given a variable as a variable index, including the equations containing
  the state variable but not its derivative. This must be used to update
  equations when a state is changed to algebraic variable in index reduction
  using dummy derivatives.
  These equation indices are represented with negative index, thus all
  indices are mapped trough int_abs (absolute value).
  inputs:  (IncidenceMatrixT, int /* variable */)
  outputs:  int list /* equations */"
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  input Integer inInteger;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inIncidenceMatrixT,inInteger)
    local
      Integer n,indx;
      list<Integer> res,res_1;
      array<list<Integer>> mt;
      String s;
    
    case (mt,n)
      equation
        res = mt[n];
        res_1 = List.map(res, intAbs);
      then
        res_1;
    
    case (_,indx)
      equation
        print("- BackendDAEUtil.eqnsForVarWithStates failed, indx= ");
        s = intString(indx);
        print(s);
        print("\n");
      then
        fail();
  end matchcontinue;
end eqnsForVarWithStates;

public function varsInEqn
"function: varsInEqn
  author: PA
  This function returns all variable indices as a list for
  a given equation, given as an equation index. (1...n)
  Negative indexes are removed.
  See also: eqnsForVar and eqnsForVarWithStates
  inputs:  (IncidenceMatrix, int /* equation */)
  outputs:  int list /* variables */"
  input BackendDAE.IncidenceMatrix m;
  input Integer indx;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (m,indx)
    local String s;
    case (_,_)
      then
        removeNegative(m[indx]);
    else
      equation
        s = "- BackendDAEUtil.varsInEqn failed, indx= " +& intString(indx) +& "array length: " +& intString(arrayLength(m)) +& "\n";
        Error.addMessage(Error.INTERNAL_ERROR,{s});
      then
        fail();
  end matchcontinue;
end varsInEqn;

public function varsInEqnEnhanced
"function: varsInEqnEnhanced
  author: Frenkel TUD
  This function returns all variable indices as a list for
  a given equation, given as an equation index. (1...n)
  Negative indexes are removed.
  See also: eqnsForVar and eqnsForVarWithStates
  inputs:  (AdjacencyMatrixEnhanced, tuple(int,Solvability) /* equation */)
  outputs:  int list /* variables */"
  input BackendDAE.AdjacencyMatrixEnhanced m;
  input Integer indx;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := List.fold(m[indx],varsInEqnEnhanced1,{});
end varsInEqnEnhanced;

public function varsInEqnEnhanced1
"function: varsInEqnEnhanced
  author: Frenkel TUD
  This function returns all variable indices as a list for
  a given equation, given as an equation index. (1...n)
  Negative indexes are removed.
  See also: eqnsForVar and eqnsForVarWithStates
  inputs:  (AdjacencyMatrixEnhanced, tuple(int,Solvability) /* equation */)
  outputs:  int list /* variables */"
  input BackendDAE.AdjacencyMatrixElementEnhancedEntry m;
  input list<Integer> iAcc;
  output list<Integer> oAcc;
protected
  Integer i;
algorithm
  (i,_) := m;
  oAcc := List.consOnTrue(intGt(i,0),i,iAcc);
end varsInEqnEnhanced1;

public function subscript2dCombinations
"function: susbscript2dCombinations
  This function takes two lists of list of subscripts and combines them in
  all possible combinations. This is used when finding all indexes of a 2d
  array.
  For instance, subscript2dCombinations({{a},{b},{c}},{{x},{y},{z}})
  => {{a,x},{a,y},{a,z},{b,x},{b,y},{b,z},{c,x},{c,y},{c,z}}
  inputs:  (DAE.Subscript list list /* dim1 subs */,
              DAE.Subscript list list /* dim2 subs */)
  outputs: (DAE.Subscript list list)"
  input list<list<DAE.Subscript>> inExpSubscriptLstLst1;
  input list<list<DAE.Subscript>> inExpSubscriptLstLst2;
  output list<list<DAE.Subscript>> outExpSubscriptLstLst;
algorithm
  outExpSubscriptLstLst := match (inExpSubscriptLstLst1,inExpSubscriptLstLst2)
    local
      list<list<DAE.Subscript>> lst1,lst2,res,ss,ss2;
      list<DAE.Subscript> s1;
    
    case ({},_) then {};
    
    case ((s1 :: ss),ss2)
      equation
        lst1 = subscript2dCombinations2(s1, ss2);
        lst2 = subscript2dCombinations(ss, ss2);
        res = listAppend(lst1, lst2);
      then
        res;
  end match;
end subscript2dCombinations;

protected function subscript2dCombinations2
  input list<DAE.Subscript> inExpSubscriptLst;
  input list<list<DAE.Subscript>> inExpSubscriptLstLst;
  output list<list<DAE.Subscript>> outExpSubscriptLstLst;
algorithm
  outExpSubscriptLstLst := match (inExpSubscriptLst,inExpSubscriptLstLst)
    local
      list<list<DAE.Subscript>> lst1,ss2;
      list<DAE.Subscript> elt1,ss,s2;
    
    case (_,{}) then {};
    
    case (ss,(s2 :: ss2))
      equation
        lst1 = subscript2dCombinations2(ss, ss2);
        elt1 = listAppend(ss, s2);
      then
        (elt1 :: lst1);
  end match;
end subscript2dCombinations2;

public function splitoutEquationAndVars
" author: wbraun"
  input BackendDAE.StrongComponents inNeededBlocks;
  input EquationArray inEqns;
  input BackendDAE.Variables inVars;
  input EquationArray inEqnsNew;
  input BackendDAE.Variables inVarsNew;
  output EquationArray outEqns;
  output BackendDAE.Variables outVars;
algorithm 
  (outEqns,outVars) := matchcontinue(inNeededBlocks,inEqns,inVars, inEqnsNew, inVarsNew)
  local
    BackendDAE.StrongComponent comp;
    BackendDAE.StrongComponents rest;
    BackendDAE.Equation eqn;
    Var var;
    list<BackendDAE.Equation> eqn_lst;
    list<Var> var_lst;
    EquationArray eqnsNew;
    BackendDAE.Variables varsNew;
    case ({},inEqns,inVars,eqnsNew,varsNew) then (eqnsNew,varsNew);
    case (comp::rest,inEqns,inVars,eqnsNew,varsNew)
      equation
      (eqnsNew,varsNew) = splitoutEquationAndVars(rest,inEqns,inVars,eqnsNew,varsNew);
      (eqn_lst,var_lst,_) = BackendDAETransform.getEquationAndSolvedVar(comp, inEqns, inVars);
      eqnsNew = BackendEquation.addEquations(eqn_lst, eqnsNew);
      varsNew = BackendVariable.addVars(var_lst, varsNew);
    then (eqnsNew,varsNew);
 end matchcontinue;
end splitoutEquationAndVars;

public function whenClauseAddDAE
"function: whenClauseAddDAE
  author: Frenkel TUD 2011-05"
  input list<WhenClause> inWcLst;
  input BackendDAE.Shared shared;
  output BackendDAE.Shared oshared;
algorithm
  oshared := match (inWcLst,shared)
    local
      BackendDAE.Variables knvars,exobj,aliasVars;
      EquationArray remeqns,inieqns;
      array<DAE.Constraint> constrs;
      array<DAE.ClassAttributes> clsAttrs;
      Env.Cache cache;
      Env.Env env;      
      DAE.FunctionTree funcs;
      list<WhenClause> wclst,wclst1;
      list<ZeroCrossing> zc, rellst, smplLst;
      Integer numberOfRelations;
      ExternalObjectClasses eoc;
      BackendDAE.SymbolicJacobians symjacs;
      BackendDAEType btp;
    case (_,BackendDAE.SHARED(knvars,exobj,aliasVars,inieqns,remeqns,constrs,clsAttrs,cache,env,funcs,BackendDAE.EVENT_INFO(wclst,zc,smplLst,rellst,numberOfRelations),eoc,btp,symjacs))
      equation
        wclst1 = listAppend(wclst,inWcLst);  
      then BackendDAE.SHARED(knvars,exobj,aliasVars,inieqns,remeqns,constrs,clsAttrs,cache,env,funcs,BackendDAE.EVENT_INFO(wclst1,zc,smplLst,rellst,numberOfRelations),eoc,btp,symjacs);
  end match;
end whenClauseAddDAE;

public function getStrongComponents
"function: getStrongComponents
  author: Frenkel TUD 2011-11
  This function returns the strongComponents of a BackendDAE."
  input BackendDAE.EqSystem syst;
  output BackendDAE.StrongComponents outComps;
algorithm
  BackendDAE.EQSYSTEM(matching=BackendDAE.MATCHING(comps=outComps)) := syst;
end getStrongComponents;

public function getFunctions
"function: getFunctions
  author: Frenkel TUD 2011-11
  This function returns the Functions of a BackendDAE."
  input BackendDAE.Shared shared;
  output DAE.FunctionTree functionTree;
algorithm
  BackendDAE.SHARED(functionTree=functionTree) := shared;
end getFunctions;

/************************************
  stuff that deals with extendArrExp
 ************************************/

public function extendArrExp "
Author: Frenkel TUD 2010-07
alternative name: vectorizeExp
"
  input tuple<DAE.Exp,tuple<Option<DAE.FunctionTree>,Boolean>> itpl;
  output tuple<DAE.Exp,tuple<Option<DAE.FunctionTree>,Boolean>> otpl;
algorithm 
  otpl := matchcontinue itpl
    local
      DAE.Exp e;
      Option<DAE.FunctionTree> funcs;
    case ((e,(funcs,_))) then Expression.traverseExp(e, traversingextendArrExp, (funcs,false));
    case _ then itpl;
  end matchcontinue;
end extendArrExp;

protected function traversingextendArrExp "
Author: Frenkel TUD 2010-07.
  This function extend all array and record componentrefs to there
  elements. This is necessary for BLT and substitution of simple 
  equations."
  input tuple<DAE.Exp, tuple<Option<DAE.FunctionTree>,Boolean> > inExp;
  output tuple<DAE.Exp, tuple<Option<DAE.FunctionTree>,Boolean> > outExp;
algorithm outExp := matchcontinue(inExp)
  local
    Option<DAE.FunctionTree> funcs;
    DAE.ComponentRef cr;
    list<DAE.ComponentRef> crlst;
    DAE.Type t,ty;
    DAE.Dimension id, jd;
    list<DAE.Dimension> ad;
    Integer i,j;
    list<list<DAE.Subscript>> subslst,subslst1;
    list<DAE.Exp> expl;
    DAE.Exp e_new;
    list<DAE.Var> varLst;
    Absyn.Path name;
    tuple<DAE.Exp, tuple<Option<DAE.FunctionTree>,Boolean> > restpl;
    list<list<DAE.Exp>> mat;
    Boolean b;
    
  // CASE for Matrix    
  case( (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad as {id, jd})), (funcs,_)) )
    equation
        i = Expression.dimensionSize(id);
        j = Expression.dimensionSize(jd);
        subslst = dimensionsToRange(ad);
        subslst1 = rangesToSubscripts(subslst);
        cr = ComponentReference.crefStripLastSubs(cr);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,Expression.makeCrefExp,ty);
        mat = makeMatrix(expl,j,j,{});
        e_new = DAE.MATRIX(t,i,mat);
        restpl = Expression.traverseExp(e_new, traversingextendArrExp, (funcs,true));
    then
      (restpl);
  
  // CASE for Matrix and checkModel is on    
  case( (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad as {id, jd})), (funcs,_)) )
    equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
        // consider size 1
        i = Expression.dimensionSize(DAE.DIM_INTEGER(1));
        j = Expression.dimensionSize(DAE.DIM_INTEGER(1));
        subslst = dimensionsToRange(ad);
        subslst1 = rangesToSubscripts(subslst);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,Expression.makeCrefExp,ty);
        mat = makeMatrix(expl,j,j,{});
        e_new = DAE.MATRIX(t,i,mat);
        restpl = Expression.traverseExp(e_new, traversingextendArrExp, (funcs,true));
    then
      (restpl);
  
  // CASE for Array
  case( (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad)), (funcs,_)) )
    equation
        subslst = dimensionsToRange(ad);
        subslst1 = rangesToSubscripts(subslst);
        cr = ComponentReference.crefStripLastSubs(cr);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,Expression.makeCrefExp,ty);
        e_new = DAE.ARRAY(t,true,expl);
        restpl = Expression.traverseExp(e_new, traversingextendArrExp, (funcs,true));
    then
      (restpl);

  // CASE for Array and checkModel is on
  case( (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad)), (funcs,b)) )
    equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
        // consider size 1      
        subslst = dimensionsToRange({DAE.DIM_INTEGER(1)});
        subslst1 = rangesToSubscripts(subslst);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,Expression.makeCrefExp,ty);
        e_new = DAE.ARRAY(t,true,expl);
        restpl = Expression.traverseExp(e_new, traversingextendArrExp, (funcs,true));
    then
      (restpl);
  // CASE for Records
  case( (DAE.CREF(componentRef=cr,ty= t as DAE.T_COMPLEX(varLst=varLst,complexClassType=ClassInf.RECORD(name))), (funcs,_)) )
    equation
        expl = List.map1(varLst,Expression.generateCrefsExpFromExpVar,cr);
        i = listLength(expl);
        true = intGt(i,0);
        e_new = DAE.CALL(name,expl,DAE.CALL_ATTR(t,false,false,DAE.NO_INLINE(),DAE.NO_TAIL()));
        restpl = Expression.traverseExp(e_new, traversingextendArrExp, (funcs,true));
    then 
      (restpl);
  case _ then inExp;
end matchcontinue;
end traversingextendArrExp;

protected function makeMatrix
  input list<DAE.Exp> expl;
  input Integer r;
  input Integer n;
  input list<DAE.Exp> incol;
  output list<list<DAE.Exp>> scalar;
algorithm
  scalar := matchcontinue (expl, r, n, incol)
    local 
      DAE.Exp e;
      list<DAE.Exp> rest;
      list<list<DAE.Exp>> res;
      list<DAE.Exp> col;
  case({},_,_,_)
    equation
      col = listReverse(incol);
    then {col};
  case(e::rest,_,_,_)
    equation
      true = intEq(r,0);
      col = listReverse(incol);
      res = makeMatrix(e::rest,n,n,{});
    then      
      (col::res);
  case(e::rest,_,_,_)
    equation
      res = makeMatrix(rest,r-1,n,e::incol);
    then      
      res;
  end matchcontinue;
end makeMatrix;

public function removediscreteAssingments "
Author: wbraun
Function tarverse Statements and remove discrete one"
  input list<DAE.Statement> inStmts;
  input BackendDAE.Variables inVars;
  output list<DAE.Statement> outStmts;
algorithm 
  outStmts := matchcontinue(inStmts,inVars)
    local 
      list<DAE.Statement> stmts,rest,xs;
      DAE.Else algElse;
      DAE.Statement stmt,ew;
      DAE.ComponentRef cref;
      Var v;
      BackendDAE.Variables vars;
      DAE.Exp e;
      DAE.ElementSource source;
      
      DAE.Type tp;
      Boolean b1;
      String id1;
      list<Integer> li;
      Integer index;
    case ({},_) then ({});
      
    case ((DAE.STMT_ASSIGN(exp1 = e) :: rest),vars)
      equation
        cref = Expression.expCref(e);
        ({v},_) = BackendVariable.getVar(cref,vars);
        true = BackendVariable.isVarDiscrete(v);
        xs = removediscreteAssingments(rest,vars);
      then xs;
        
    /*case ((DAE.STMT_TUPLE_ASSIGN(expExpLst = expl1) :: rest),vars)
      equation
        crefLst = List.map(expl1,Expression.expCref);
        (vlst,_) = List.map1_2(crefLst,BackendVariable.getVar,vars);
        //blst = List.map(vlst,BackendVariable.isVarDiscrete);
        //true = boolOrList(blst);
        xs = removediscreteAssingments(rest,vars);
      then xs;
      */  
    case ((DAE.STMT_ASSIGN_ARR(componentRef = cref) :: rest),vars)
      equation
        ({v},_) = BackendVariable.getVar(cref,vars);
        true = BackendVariable.isVarDiscrete(v);
        xs = removediscreteAssingments(rest,vars);
      then xs;
        
    case (((DAE.STMT_IF(exp=e,statementLst=stmts,else_ = algElse, source = source)) :: rest),vars)
      equation
        stmts = removediscreteAssingments(stmts,vars);
        algElse = removediscreteAssingmentsElse(algElse,vars);
        xs = removediscreteAssingments(rest,vars);
      then DAE.STMT_IF(e,stmts,algElse,source) :: xs;
        
    case (((DAE.STMT_FOR(type_=tp,iterIsArray=b1,iter=id1,index=index,range=e,statementLst=stmts, source = source)) :: rest),vars)
      equation
        stmts = removediscreteAssingments(stmts,vars);
        xs = removediscreteAssingments(rest,vars);
      then DAE.STMT_FOR(tp,b1,id1,index,e,stmts,source) :: xs;
        
    case (((DAE.STMT_WHILE(exp = e,statementLst=stmts, source = source)) :: rest),vars)
      equation
        stmts = removediscreteAssingments(stmts,vars);
        xs = removediscreteAssingments(rest,vars);
      then DAE.STMT_WHILE(e,stmts,source) :: xs;
    case (((DAE.STMT_WHEN(exp = e,statementLst=stmts,elseWhen=NONE(),helpVarIndices=li, source = source)) :: rest),vars)
        
      equation
        stmts = removediscreteAssingments(stmts,vars);
        xs = removediscreteAssingments(rest,vars);
      then DAE.STMT_WHEN(e,stmts,NONE(),li,source) :: xs;
        
    case (((DAE.STMT_WHEN(exp = e,statementLst=stmts,elseWhen=SOME(ew),helpVarIndices=li, source = source)) :: rest),vars)
      equation
        stmts = removediscreteAssingments(stmts,vars);
        {ew} = removediscreteAssingments({ew},vars);
        xs = removediscreteAssingments(rest,vars);
      then DAE.STMT_WHEN(e,stmts,SOME(ew),li,source) :: xs;
        
    case ((stmt :: rest),vars)
      equation
        xs = removediscreteAssingments(rest,vars);
      then  stmt :: xs;
  end matchcontinue;
end removediscreteAssingments;

protected function removediscreteAssingmentsElse "
Author: wbraun
Helper function for traverseDAEEquationsELse
"
  input DAE.Else inElse;
  input BackendDAE.Variables inVars;
  output DAE.Else outElse;
algorithm 
  outElse := match(inElse,inVars)
  local
    DAE.Exp e;
    list<DAE.Statement> st;
    DAE.Else el;
    BackendDAE.Variables vars;
  case(DAE.NOELSE(),_) then (DAE.NOELSE());
  case(DAE.ELSEIF(e,st,el),vars)
    equation
      el = removediscreteAssingmentsElse(el,vars);
      st = removediscreteAssingments(st,vars);
    then DAE.ELSEIF(e,st,el);
  case(DAE.ELSE(st),vars)
    equation
      st = removediscreteAssingments(st,vars);
    then DAE.ELSE(st);
end match;
end removediscreteAssingmentsElse;

public function collateAlgorithm "
Author: Frenkel TUD 2010-07"
  input DAE.Algorithm inAlg;
  input Option<DAE.FunctionTree> infuncs;
  output DAE.Algorithm outAlg;
algorithm 
  outAlg := matchcontinue(inAlg,infuncs)
    local list<DAE.Statement> statementLst;
    case(DAE.ALGORITHM_STMTS(statementLst=statementLst),_)
      equation
        (statementLst,_) = DAEUtil.traverseDAEStmts(statementLst, collateArrExpStmt, infuncs);
      then
        DAE.ALGORITHM_STMTS(statementLst);
    case (_,_) then inAlg;
  end matchcontinue;
end collateAlgorithm;

protected function collateArrExpStmt
" Author: Frenkel TUD 2010-07
  wbraun: added as workaround for when condition.
  As long as we don't support fully array helpVars, we
  we can't collate the expression of a when condition.
  "
  input tuple<DAE.Exp, DAE.Statement, Option<DAE.FunctionTree>> itpl;
  output tuple<DAE.Exp, Option<DAE.FunctionTree>> otpl;
algorithm 
  otpl := matchcontinue itpl
    local
      DAE.Exp e;
      DAE.Statement x;
      Option<DAE.FunctionTree> funcs;
    case ((e, x, funcs))
      equation
       ((e, (_, _))) = Expression.traverseExp(e, traversingcollateArrExpStmt, (x, funcs));
      then ((e,funcs));
    case ((e, x, funcs)) then ((e,funcs));
  end matchcontinue;
end collateArrExpStmt;
  
protected function traversingcollateArrExpStmt "
Author: Frenkel TUD 2010-07.
  wbraun: added as workaround for when condition.
  As long as we don't support fully array helpVars, we
  we can't collate the expression of a when condition.
"
  input tuple<DAE.Exp, tuple<DAE.Statement, Option<DAE.FunctionTree>> > inExp;
  output tuple<DAE.Exp, tuple<DAE.Statement, Option<DAE.FunctionTree>> > outExp;
algorithm outExp := matchcontinue(inExp)
  local
    Option<DAE.FunctionTree> funcs;
    DAE.ComponentRef cr;
    DAE.Type ty;
    Integer i;
    DAE.Exp e,e1,e1_1,e1_2;
    Boolean b;
    DAE.Statement x;
    // do nothing if try to collate when codition expression
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=((e1 as DAE.CREF(componentRef = cr))::_)::_), (x as DAE.STMT_WHEN(exp=_), funcs)))
      then     
        ((e,(x,funcs)));
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=(((e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr))))::_)::_), (x as DAE.STMT_WHEN(exp=_), funcs)))
      then     
        ((e,(x,funcs)));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.CREF(componentRef = cr))::_), (x as DAE.STMT_WHEN(exp=_), funcs)))
      then     
        ((e,(x,funcs)));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr)))::_), (x as DAE.STMT_WHEN(exp=_), funcs)))
      then     
        ((e,(x,funcs)));
     // collate in other cases
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=((e1 as DAE.CREF(componentRef = cr))::_)::_), (x, funcs)))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,(x,funcs)));
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=(((e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr))))::_)::_), (x, funcs)))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,(x,funcs)));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.CREF(componentRef = cr))::_), (x, funcs)))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,(x,funcs)));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr)))::_), (x, funcs)))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,(x,funcs)));
  case _ then inExp;
end matchcontinue;
end traversingcollateArrExpStmt;

public function collateArrExpList
"function collateArrExpList
 author Frenkel TUD:
  replace {a[1],a[2],a[3]} for Real a[3] with a"
  input list<DAE.Exp> iexpl;
  input Option<DAE.FunctionTree> optfunc;
  output list<DAE.Exp> outexpl;
algorithm
  outexpl := match(iexpl,optfunc)
    local 
      DAE.Exp e,e1;
      list<DAE.Exp> expl1,expl;
    
    case({},_) then {};
   
    case(e::expl,_) equation
      ((e1,_)) = collateArrExp((e,optfunc));
      expl1 = collateArrExpList(expl,optfunc);
    then 
      e1::expl1;
  end match;
end collateArrExpList;

public function collateArrExp "
Author: Frenkel TUD 2010-07"
  input tuple<DAE.Exp, Option<DAE.FunctionTree>> itpl;
  output tuple<DAE.Exp,Option<DAE.FunctionTree>> otpl;
algorithm 
  otpl := matchcontinue itpl
    local
      DAE.Exp e;
      Option<DAE.FunctionTree> funcs;
    case ((e,funcs)) then Expression.traverseExp(e, traversingcollateArrExp, funcs);
    case _ then itpl;
  end matchcontinue;
end collateArrExp;
  
protected function traversingcollateArrExp "
Author: Frenkel TUD 2010-07."
  input tuple<DAE.Exp, Option<DAE.FunctionTree> > inExp;
  output tuple<DAE.Exp, Option<DAE.FunctionTree> > outExp;
algorithm outExp := matchcontinue(inExp)
  local
    Option<DAE.FunctionTree> funcs;
    DAE.ComponentRef cr;
    DAE.Type ty;
    Integer i;
    DAE.Exp e,e1,e1_1,e1_2;
    Boolean b;
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=((e1 as DAE.CREF(componentRef = cr))::_)::_),funcs))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,funcs));
    case ((e as DAE.MATRIX(ty=ty,integer=i,matrix=(((e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr))))::_)::_),funcs))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,funcs));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.CREF(componentRef = cr))::_),funcs))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,funcs));
    case ((e as DAE.ARRAY(ty=ty,scalar=b,array=(e1 as DAE.UNARY(exp = DAE.CREF(componentRef = cr)))::_),funcs))
      equation
        e1_1 = Expression.expStripLastSubs(e1);
        ((e1_2,(_,true))) = extendArrExp((e1_1,(funcs,false)));
        true = Expression.expEqual(e,e1_2);
      then     
        ((e1_1,funcs));
  case _ then inExp;
end matchcontinue;
end traversingcollateArrExp;

public function dimensionsToRange
  "Converts a list of dimensions to a list of integer ranges."
  input list<DAE.Dimension> idims;
  output list<list<DAE.Subscript>> outRangelist;
algorithm
  outRangelist := matchcontinue(idims)
  local 
    Integer i;
    list<list<DAE.Subscript>> rangelist;
    list<Integer> range;
    list<DAE.Subscript> subs;
    DAE.Dimension d;
    list<DAE.Dimension> dims;
    
    case({}) then {};
    case(DAE.DIM_UNKNOWN()::dims) 
      equation
        rangelist = dimensionsToRange(dims);
      then {}::rangelist;
    case(d::dims) equation
      i = Expression.dimensionSize(d);
      range = List.intRange(i);
      subs = rangesToSubscript(range);
      rangelist = dimensionsToRange(dims);
    then subs::rangelist;
  end matchcontinue;
end dimensionsToRange;

public function rangesToSubscript "
Author: Frenkel TUD 2010-05"
  input list<Integer> inRange;
  output list<DAE.Subscript> outSubs;
algorithm
  outSubs := match(inRange)
  local 
    Integer i;
    list<Integer> res;
    list<DAE.Subscript> range;
    case({}) then {};
    case(i::res) 
      equation
        range = rangesToSubscript(res);
      then DAE.INDEX(DAE.ICONST(i))::range;
  end match;
end rangesToSubscript;

public function rangesToSubscripts "
Author: Frenkel TUD 2010-05"
  input list<list<DAE.Subscript>> inRangelist;
  output list<list<DAE.Subscript>> outSubslst;
algorithm
  outSubslst := matchcontinue(inRangelist)
  local 
    list<list<DAE.Subscript>> rangelist,rangelist1;
    list<list<list<DAE.Subscript>>> rangelistlst;
    list<DAE.Subscript> range;
    case({}) then {};
    case(range::{})
      equation
        rangelist = List.map(range,List.create);
      then rangelist;
    case(range::rangelist)
      equation
      rangelist = rangesToSubscripts(rangelist);
      rangelistlst = List.map1(range,rangesToSubscripts1,rangelist);
      rangelist1 = List.flatten(rangelistlst);
    then rangelist1;
  end matchcontinue;
end rangesToSubscripts;

protected function rangesToSubscripts1 "
Author: Frenkel TUD 2010-05"
  input DAE.Subscript inSub;
  input list<list<DAE.Subscript>> inRangelist;
  output list<list<DAE.Subscript>> outSubslst;
algorithm
  outSubslst := List.map1(inRangelist, List.consr, inSub);
end rangesToSubscripts1;

public function getEquationBlock"function: getEquationBlock
  author: PA

  Returns the block the equation belongs to.
"
  input Integer inInteger;
  input BackendDAE.StrongComponents inComps;
  output BackendDAE.StrongComponent outComp;
algorithm
  outComp:=
  matchcontinue (inInteger,inComps)
    local
      Integer i;
      list<Integer> elst;
      BackendDAE.StrongComponents comps;
      BackendDAE.StrongComponent comp;
    case (i,comp::comps)
      equation
        (elst,_) = BackendDAETransform.getEquationAndSolvedVarIndxes(comp);
        true = listMember(i,elst);        
      then
        comp;          
    case (i,_::comps)
      equation
        comp = getEquationBlock(i,comps);
      then
        comp;
  end matchcontinue;
end getEquationBlock;

/******************************************************************
 stuff to calculate incidence matrix
  
 wbraun: It should be renames to Adjacency matrix, because
    incidence matrix descibes the relation between knots and edges. 
    In the sense it is used here is the relation between knots and
    knots of a bigraph.
******************************************************************/

public function incidenceMatrix
"function: incidenceMatrix
  author: PA, adrpo
  Calculates the incidence matrix, i.e. which variables are present in each equation.
  You can ask for absolute indexes or normal (negative for der) via the IndexType.
    wbraun: beware dim(IncidenceMatrix) != dim(IncidenceMatrixT) due to array equations. "
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndexType;
  output BackendDAE.IncidenceMatrix outIncidenceMatrix;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT) := matchcontinue (syst, inIndexType)
    local
      BackendDAE.IncidenceMatrix arr;
      BackendDAE.IncidenceMatrixT arrT;
      BackendDAE.Variables vars;
      EquationArray eqns;
      Integer numberOfEqs,numberofVars;
    
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns), _)
      equation
        // get the size
        numberOfEqs = equationArraySize(eqns);
        numberofVars = BackendVariable.varsSize(vars);
        // create the array to hold the incidence matrix
        arrT = arrayCreate(numberofVars, {});
        (arr,arrT) = incidenceMatrixDispatch(vars, eqns, {},arrT, 0, numberOfEqs, intLt(0, numberOfEqs), inIndexType);
      then
        (arr,arrT);
    
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.incidenceMatrix failed"});
      then
        fail();
  end matchcontinue;
end incidenceMatrix;

public function incidenceMatrixScalar
"function: incidenceMatrixScalar
  author: PA, adrpo
  Calculates the incidence matrix, i.e. which variables are present in each equation.
  You can ask for absolute indexes or normal (negative for der) via the IndexType"
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndexType;
  output BackendDAE.IncidenceMatrix outIncidenceMatrix;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
  output array<list<Integer>> outMapEqnIncRow;
  output array<Integer> outMapIncRowEqn;
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT,outMapEqnIncRow,outMapIncRowEqn) := 
  matchcontinue (syst, inIndexType)
    local
      BackendDAE.IncidenceMatrix arr;
      BackendDAE.IncidenceMatrixT arrT;
      BackendDAE.Variables vars;
      EquationArray eqns;
      Integer numberOfEqs,numberofVars;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;
    
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns), _)
      equation
        // get the size
        numberOfEqs = equationArraySize(eqns);
        numberofVars = BackendVariable.varsSize(vars);
        // create the array to hold the incidence matrix
        arrT = arrayCreate(numberofVars, {});
        (arr,arrT,mapEqnIncRow,mapIncRowEqn) = incidenceMatrixDispatchScalar(vars, eqns, {},arrT, 0, numberOfEqs, intLt(0, numberOfEqs), inIndexType, 0, {}, {});
      then
        (arr,arrT,mapEqnIncRow,mapIncRowEqn);
    
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.incidenceMatrixScalar failed"});
      then
        fail();
  end matchcontinue;
end incidenceMatrixScalar;

public function applyIndexType
"@author: adrpo
  Applies absolute value to all entries in the given list."
  input list<Integer> inLst;
  input BackendDAE.IndexType inIndexType;
  output list<Integer> outLst;
algorithm
  outLst := match(inLst, inIndexType)
    
    // transform to absolute indexes
    case (_, BackendDAE.ABSOLUTE()) then Util.absIntegerList(inLst);
    
    // leave as it is 
    case (_, _) then inLst;
    

  end match;
end applyIndexType;

protected function incidenceMatrixDispatch
"@author: adrpo
  Calculates the incidence matrix as an array of list of integers"
  input BackendDAE.Variables vars;
  input EquationArray inEqsArr;
  input list<BackendDAE.IncidenceMatrixElement> inIncidenceArray;
  input BackendDAE.IncidenceMatrixT inIncidenceArrayT;
  input Integer index;
  input Integer numberOfEqs;
  input Boolean stop;
  input BackendDAE.IndexType inIndexType;
  output BackendDAE.IncidenceMatrix outIncidenceArray;
  output BackendDAE.IncidenceMatrixT outIncidenceArrayT;
algorithm
  (outIncidenceArray,outIncidenceArrayT) := 
    match (vars, inEqsArr, inIncidenceArray, inIncidenceArrayT, index, numberOfEqs, stop, inIndexType)
    local
      list<Integer> row;
      BackendDAE.Equation e;
      list<BackendDAE.IncidenceMatrixElement> iArr;
      BackendDAE.IncidenceMatrix iArrT;
      Integer i1;
    
    // i = n (we reach the end)
    case (_, _, iArr, iArrT, _, _, false, _) then (listArray(listReverse(iArr)),iArrT);
    
    // i < n 
    case (_, _, iArr, iArrT, _, _, true, _)
      equation
        // get the equation
        e = equationNth(inEqsArr, index);
        // compute the row
        (row,_) = incidenceRow(e, vars, inIndexType, {});
        i1 = index+1;       
        // put it in the arrays
        iArr = row::iArr;
        iArrT = fillincidenceMatrixT(row,{i1},iArrT);
        // next equation
        (outIncidenceArray,iArrT) = incidenceMatrixDispatch(vars, inEqsArr, iArr, iArrT, i1, numberOfEqs, intLt(i1, numberOfEqs), inIndexType);
      then
        (outIncidenceArray,iArrT);
    
    /* Unreachable due to tail recursion, which we really need
    case (vars, eqArr, wc, iArr, iArrT, i, n, inIndexType)
      equation
        print("- BackendDAEUtil.incidenceMatrixDispatch failed\n");
      then
        fail();
    */
  end match;
end incidenceMatrixDispatch;

protected function incidenceMatrixDispatchScalar
"@author: adrpo
  Calculates the incidence matrix as an array of list of integers"
  input BackendDAE.Variables vars;
  input EquationArray inEqsArr;
  input list<BackendDAE.IncidenceMatrixElement> inIncidenceArray;
  input BackendDAE.IncidenceMatrixT inIncidenceArrayT;
  input Integer index;
  input Integer numberOfEqs;
  input Boolean stop;
  input BackendDAE.IndexType inIndexType;
  input Integer inRowSize;
  input list<list<Integer>> imapEqnIncRow;
  input list<Integer> imapIncRowEqn;
  output BackendDAE.IncidenceMatrix outIncidenceArray;
  output BackendDAE.IncidenceMatrixT outIncidenceArrayT;
  output array<list<Integer>> omapEqnIncRow;
  output array<Integer> omapIncRowEqn;
algorithm
  (outIncidenceArray,outIncidenceArrayT,omapEqnIncRow,omapIncRowEqn) := 
    match (vars, inEqsArr, inIncidenceArray, inIncidenceArrayT, index, numberOfEqs, stop, inIndexType, inRowSize, imapEqnIncRow, imapIncRowEqn)
    local
      list<Integer> row,rowindxs,mapIncRowEqn;
      BackendDAE.Equation e;
      list<BackendDAE.IncidenceMatrixElement> iArr;
      BackendDAE.IncidenceMatrix iArrT;
      Integer i1,rowSize,size;
    
    // i = n (we reach the end)
    case (_, _, iArr, iArrT, _, _, false, _, _, _, _) then (listArray(listReverse(iArr)),iArrT,listArray(listReverse(imapEqnIncRow)),listArray(listReverse(imapIncRowEqn)));
    
    // i < n 
    case (_, _, iArr, iArrT, _, _, true, _, _, _, _)
      equation
        // get the equation
        e = equationNth(inEqsArr, index);
        // compute the row
        (row,size) = incidenceRow(e, vars, inIndexType, {});
        rowSize = inRowSize + size;
        rowindxs = List.intRange2(inRowSize+1, rowSize);
        i1 = index+1;
        mapIncRowEqn = List.consN(size,i1,imapIncRowEqn);        
        // put it in the arrays
        iArr = List.consN(size,row,iArr);
        iArrT = fillincidenceMatrixT(row,rowindxs,iArrT);
        // next equation
        (outIncidenceArray,iArrT,omapEqnIncRow,omapIncRowEqn) = incidenceMatrixDispatchScalar(vars, inEqsArr, iArr, iArrT, i1, numberOfEqs, intLt(i1, numberOfEqs), inIndexType, rowSize, rowindxs::imapEqnIncRow, mapIncRowEqn);
      then
        (outIncidenceArray,iArrT,omapEqnIncRow,omapIncRowEqn);
    
    /* Unreachable due to tail recursion, which we really need
    case (vars, eqArr, wc, iArr, iArrT, i, n, inIndexType)
      equation
        print("- BackendDAEUtil.incidenceMatrixDispatchScalar failed\n");
      then
        fail();
    */
  end match;
end incidenceMatrixDispatchScalar;

protected function fillincidenceMatrixT
"@author: Frenkel TUD 2011-04
  inserts the equation numbers"
  input BackendDAE.IncidenceMatrixElement eqns;
  input list<Integer> eqnsindxs;
  input BackendDAE.IncidenceMatrixT inIncidenceArrayT;
  output BackendDAE.IncidenceMatrixT outIncidenceArrayT;
algorithm
  outIncidenceArrayT := matchcontinue (eqns, eqnsindxs, inIncidenceArrayT)
    local
      BackendDAE.IncidenceMatrixElement row,rest,newrow;
      Integer v,vabs;
      BackendDAE.IncidenceMatrixT mT,mT1;
    
    case ({},_,_) then inIncidenceArrayT;
    
    case (v::rest,_,_)
      equation
        true = intLt(0, v);
        row = inIncidenceArrayT[v];
        // put it in the array
        newrow = listAppend(eqnsindxs,row);
        mT = arrayUpdate(inIncidenceArrayT, v, newrow);
        mT1 = fillincidenceMatrixT(rest, eqnsindxs, mT);
      then
        mT1;
        
    case (v::rest,_,_)
      equation
        false = intLt(0, v);
        vabs = intAbs(v);
        row = inIncidenceArrayT[vabs];
        newrow = List.map(eqnsindxs,intNeg);
        newrow = listAppend(newrow,row);
        // put it in the array
        mT = arrayUpdate(inIncidenceArrayT, vabs, newrow);
        mT1 = fillincidenceMatrixT(rest, eqnsindxs, mT);
      then
        mT1;
    
    case (v::_,_,_)
      equation
        vabs = intAbs(v);
        print("- BackendDAEUtil.fillincidenceMatrixT failed for Var " +& intString(vabs) +& "\n");
      then
        fail();
  end matchcontinue;
end fillincidenceMatrixT;

protected function incidenceRow
"function: incidenceRow
  author: PA
  Helper function to incidenceMatrix. Calculates the indidence row
  in the matrix for one equation."
  input BackendDAE.Equation inEquation;
  input BackendDAE.Variables vars;
  input BackendDAE.IndexType inIndexType;
  input list<Integer> iRow;
  output list<Integer> outIntegerLst;
  output Integer rowSize; 
algorithm
  (outIntegerLst,rowSize) := 
   matchcontinue (inEquation,vars,inIndexType,iRow)
    local
      list<Integer> lst1,lst2,res,dimsize;
      DAE.Exp e1,e2,e,expCref,cond;
      list<DAE.Exp> expl;
      DAE.ComponentRef cr;
      BackendDAE.WhenEquation we,elsewe;
      Integer size;
      String eqnstr;
      list<DAE.Statement> statementLst;
      list<list<BackendDAE.Equation>> eqnslst;
      list<BackendDAE.Equation> eqns;
    
    // EQUATION
    case (BackendDAE.EQUATION(exp = e1,scalar = e2),_,_,_)
      equation
        lst1 = incidenceRowExp(e1, vars, iRow,inIndexType);
        res = incidenceRowExp(e2, vars, lst1,inIndexType);
      then
        (res,1);
    
    // COMPLEX_EQUATION
    case (BackendDAE.COMPLEX_EQUATION(size=size,left=e1,right=e2),_,_,_)
      equation
        lst1 = incidenceRowExp(e1, vars, iRow,inIndexType);
        res = incidenceRowExp(e2, vars, lst1,inIndexType);
      then
        (res,size);    
    
    // ARRAY_EQUATION
    case (BackendDAE.ARRAY_EQUATION(dimSize=dimsize,left=e1,right=e2),_,_,_)
      equation
        size = List.reduce(dimsize, intMul);
        lst1 = incidenceRowExp(e1, vars, iRow,inIndexType);
        res = incidenceRowExp(e2, vars, lst1,inIndexType);
      then
        (res,size);    
    
    // SOLVED_EQUATION
    case (BackendDAE.SOLVED_EQUATION(componentRef = cr,exp = e),_,_,_)
      equation
        expCref = Expression.crefExp(cr);
        lst1 = incidenceRowExp(expCref, vars, iRow,inIndexType);
        res = incidenceRowExp(e, vars, lst1,inIndexType);
      then
        (res,1);
    
    // RESIDUAL_EQUATION
    case (BackendDAE.RESIDUAL_EQUATION(exp = e),_,_,_)
      equation
        res = incidenceRowExp(e, vars, iRow,inIndexType);
      then
        (res,1);
    
    // WHEN_EQUATION
    case (BackendDAE.WHEN_EQUATION(size=size,whenEquation = we as BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=NONE())),_,_,_)
      equation
        e1 = Expression.crefExp(cr);
        lst1 = incidenceRowExp(cond, vars, iRow,inIndexType);
        lst2 = incidenceRowExp(e1, vars, lst1,inIndexType);
        res = incidenceRowExp(e2, vars, lst2,inIndexType);
      then
        (res,size);
    case (BackendDAE.WHEN_EQUATION(size=size,whenEquation = we as BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=SOME(elsewe))),_,_,_)
      equation
        e1 = Expression.crefExp(cr);
        lst1 = incidenceRowExp(cond, vars, iRow,inIndexType);
        lst2 = incidenceRowExp(e1, vars, lst1,inIndexType);
        res = incidenceRowExp(e2, vars, lst2,inIndexType);
        res = incidenceRowWhen(vars,elsewe,inIndexType,res);
      then
        (res,size);
    // ALGORITHM For now assume that algorithm will be solvable for 
    // correct variables. I.e. find all variables in algorithm and add to lst.
    // If algorithm later on needs to be inverted, i.e. solved for
    // different variables than calculated, a non linear solver or
    // analysis of algorithm itself needs to be implemented.
    case (BackendDAE.ALGORITHM(size=size,alg=DAE.ALGORITHM_STMTS(statementLst = statementLst)),_,_,_)
      equation
        ((_,res,_)) = traverseStmts(statementLst, incidenceRowAlgorithm, (vars, iRow,inIndexType));
      then
        (res,size);
        
    // if Equation
    case(BackendDAE.IF_EQUATION(conditions=expl,eqnstrue=eqnslst,eqnsfalse=eqns),_,_,_)
      equation
        res = incidenceRow1(expl, incidenceRowExp, vars, iRow,inIndexType);
        (res,_) = incidenceRowLstLst(eqnslst,vars,inIndexType,res,0);
        (res,size) = incidenceRowLst(eqns,vars,inIndexType,res,0);
      then
        (res,size);
    
    case (_,_,_,_)
      equation
        eqnstr = BackendDump.equationStr(inEquation);
        print("- BackendDAE.incidenceRow failed for eqn: ");
        print(eqnstr);
        print("\n");
      then
        fail();
  end matchcontinue;
end incidenceRow;

protected function incidenceRowLst
"function: incidenceRowLst
  author: Frenkel TUD
  Helper function to incidenceMatrix. Calculates the indidence row
  in the matrix for if equation."
  input list<BackendDAE.Equation> inEquation;
  input BackendDAE.Variables inVariables;
  input BackendDAE.IndexType inIndexType;
  input list<Integer> inIntegerLst;
  input Integer inRowSize;
  output list<Integer> outIntegerLst;
  output Integer rowSize; 
algorithm
  (outIntegerLst,rowSize) := 
   match (inEquation,inVariables,inIndexType,inIntegerLst,inRowSize)
     local
       Integer size;
       list<Integer> row;
       BackendDAE.Equation eqn;
       list<BackendDAE.Equation> eqns;
     case({},_,_,_,_) then (inIntegerLst,inRowSize);
     case(eqn::eqns,_,_,_,_)
       equation
         (row,size) = incidenceRow(eqn,inVariables,inIndexType,inIntegerLst);
         (row,size) = incidenceRowLst(eqns,inVariables,inIndexType,row,inRowSize+size);
       then
         (row,size);
  end match;
end incidenceRowLst;

protected function incidenceRowLstLst
"function: incidenceRowLst
  author: Frenkel TUD
  Helper function to incidenceMatrix. Calculates the indidence row
  in the matrix for if equation."
  input list<list<BackendDAE.Equation>> inEquation;
  input BackendDAE.Variables inVariables;
  input BackendDAE.IndexType inIndexType;
  input list<Integer> inIntegerLst;
  input Integer inRowSize;
  output list<Integer> outIntegerLst;
  output Integer rowSize; 
algorithm
  (outIntegerLst,rowSize) := 
   match (inEquation,inVariables,inIndexType,inIntegerLst,inRowSize)
     local
       Integer size;
       list<Integer> row;
       list<BackendDAE.Equation> eqn;
       list<list<BackendDAE.Equation>> eqns;
     case({},_,_,_,_) then (inIntegerLst,inRowSize);
     case(eqn::eqns,_,_,_,_)
       equation
         (row,size) = incidenceRowLst(eqn,inVariables,inIndexType,inIntegerLst,inRowSize);
         (row,size) = incidenceRowLstLst(eqns,inVariables,inIndexType,row,size);
       then
         (row,size);
  end match;
end incidenceRowLstLst;

protected function incidenceRowWhen
"function: incidenceRowWhen
  author: Frenkel TUD
  Helper function to incidenceMatrix. Calculates the indidence row
  in the matrix for a when equation."
  input BackendDAE.Variables inVariables;
  input BackendDAE.WhenEquation inEquation;
  input BackendDAE.IndexType inIndexType;
  input list<Integer> inRow;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := 
   match (inVariables,inEquation,inIndexType,inRow)
    local
      list<Integer> lst1,lst2,res;
      BackendDAE.Variables vars;
      DAE.Exp e1,e2,cond;
      DAE.ComponentRef cr;
      BackendDAE.WhenEquation elsewe;

    case (vars,BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=NONE()),_,_)
      equation
        e1 = Expression.crefExp(cr);
        lst1 = incidenceRowExp(cond, vars, inRow,inIndexType);
        lst2 = incidenceRowExp(e1, vars, lst1,inIndexType);
        res = incidenceRowExp(e2, vars, lst2,inIndexType);
      then
        res;
    case (vars,BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=SOME(elsewe)),_,_)
      equation
        e1 = Expression.crefExp(cr);
        lst1 = incidenceRowExp(cond, vars, inRow,inIndexType);
        lst2 = incidenceRowExp(e1, vars, lst1,inIndexType);
        res = incidenceRowExp(e2, vars, lst2,inIndexType);
        res = incidenceRowWhen(vars,elsewe,inIndexType,res);
      then
        res;
      
  end match;
end incidenceRowWhen;

protected function incidenceRowAlgorithm
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<Integer>,BackendDAE.IndexType>> inTpl;
  output tuple<DAE.Exp, tuple<BackendDAE.Variables,list<Integer>,BackendDAE.IndexType>> outTpl;
protected
  DAE.Exp e;
  BackendDAE.Variables vars;
  BackendDAE.IndexType ity;
  list<Integer> lst;
algorithm
  (e,(vars,lst,ity)) := inTpl;
  lst := incidenceRowExp(e,vars,lst,ity);
  outTpl := (e,(vars,lst,ity));
end incidenceRowAlgorithm;

public function incidenceRow1
  "Tail recursive implementation."
  input list<Type_a> inList;
  input FuncType inFunc;
  input Type_b inArg;
  input Type_c inArg1;
  input Type_d inArg2;
  output Type_c outArg1;

  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;
  replaceable type Type_c subtypeof Any;
  replaceable type Type_d subtypeof Any;

  partial function FuncType
    input Type_a inElem;
    input Type_b inArg;
    input Type_c inArg1;
    input Type_d inArg2;
    output Type_c outArg1;
  end FuncType;
algorithm
  outArg1 := match(inList, inFunc, inArg, inArg1, inArg2)
    local
      Type_a e1;
      list<Type_a> rest_e1;
      Type_c res,res1;
    case ({}, _, _, _, _) then inArg1;
    case (e1 :: rest_e1, _, _, _, _)
      equation
        res = inFunc(e1, inArg, inArg1, inArg2);
        res1 = incidenceRow1(rest_e1, inFunc, inArg, res, inArg2);
      then
        res1;
  end match;
end incidenceRow1;

public function incidenceRowExp
"function: incidenceRowExp
  author: PA
  Helper function to incidenceRow, investigates expressions for
  variables, returning variable indexes."
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  input list<Integer> inIntegerLst;
  input BackendDAE.IndexType inIndexType;  
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := match (inExp,inVariables,inIntegerLst,inIndexType)
    local
      list<Integer> vallst;
  case(_,_,_,BackendDAE.SPARSE())      
    equation
      ((_,(_,vallst))) = Expression.traverseExpTopDown(inExp, traversingincidenceRowExpFinderwithInput, (inVariables,inIntegerLst));
      then
        vallst;     
  case(_,_,_,BackendDAE.SOLVABLE())      
    equation
      ((_,(_,vallst))) = Expression.traverseExpTopDown(inExp, traversingincidenceRowExpSolvableFinder, (inVariables,inIntegerLst));
      then
        vallst;
  case(_,_,_,_)      
    equation
      ((_,(_,vallst))) = Expression.traverseExpTopDown(inExp, traversingincidenceRowExpFinder, (inVariables,inIntegerLst));
      // only absolute indexes?
      vallst = applyIndexType(vallst, inIndexType);      
    then
      vallst;
  end match;
end incidenceRowExp;

public function traversingincidenceRowExpSolvableFinder "
Author: Frenkel TUD 2010-11
Helper for statesAndVarsExp"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<Integer>>> inTpl;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,list<Integer>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local
      list<Integer> p,pa,res,ilst;
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      DAE.Exp e,e1,e2,startvalue,stopvalue,stepvalue;
      list<Var> varslst;
      Boolean b;
      list<DAE.Exp> explst;
      Option<DAE.Exp> stepvalueopt;
      Integer istart,istep,istop;
      list<DAE.ComponentRef> crlst;
      
    case ((e as DAE.LBINARY(exp1 = _),(vars,pa)))
      then ((e,false,(vars,pa)));        
    case ((e as DAE.RELATION(exp1 = _),(vars,pa)))
      then ((e,false,(vars,pa)));        
    case ((e as DAE.IFEXP(expThen = e1,expElse = e2),(vars,pa)))
      equation
        ((_,(vars,pa))) = Expression.traverseExpTopDown(e1, traversingincidenceRowExpSolvableFinder, (vars,pa));
        ((_,(vars,pa))) = Expression.traverseExpTopDown(e2, traversingincidenceRowExpSolvableFinder, (vars,pa));
      then
        ((e,false,(vars,pa)));
    case ((e as DAE.RANGE(ty = _),(vars,pa)))
      then ((e,false,(vars,pa))); 
    case ((e as DAE.ASUB(exp = DAE.CREF(componentRef = cr), sub=explst),(vars,pa)))
      equation
        {e1 as DAE.RANGE(start=startvalue,step=stepvalueopt,stop=stopvalue)} = ExpressionSimplify.simplifyList(explst, {});
        stepvalue = Util.getOptionOrDefault(stepvalueopt,DAE.ICONST(1));
        istart = Expression.expInt(startvalue);
        istep = Expression.expInt(stepvalue);
        istop = Expression.expInt(stopvalue);
        ilst = List.intRange3(istart,istep,istop);
        crlst = List.map1r(ilst,ComponentReference.subscriptCrefWithInt,cr);      
        (varslst,p) = BackendVariable.getVarLst(crlst,vars,{},{});
        res = incidenceRowExp1(varslst,p,pa,true);
      then ((e,false,(vars,res)));

    // if it could not simplified take all found
    case ((e as DAE.ASUB(exp = _),(vars,pa)))
      equation
        ((_,(vars,pa))) = Expression.traverseExpTopDown(e, traversingincidenceRowExpFinder, (vars,pa));
      then ((e,false,(vars,pa)));
        
    case ((e as DAE.TSUB(exp = _),(vars,pa)))
      then ((e,false,(vars,pa)));
                            
    case (((e as DAE.CREF(componentRef = cr),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,true);
      then
        ((e,false,(vars,res)));
    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));
    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));
        
    /* pre(v) is considered a known variable */
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "pre")),(vars,pa)))) then ((e,false,(vars,pa)));
    
    /* delay(e) can be used to break algebraic loops given some solver options */
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "delay"),expLst = {_,_,e1,e2}),(vars,pa))))
      equation
        b = Flags.isSet(Flags.DELAY_BREAK_LOOP) and Expression.expEqual(e1,e2);
      then ((e,not b,(vars,pa)));

    case ((e,(vars,pa))) then ((e,true,(vars,pa)));
  end matchcontinue;
end traversingincidenceRowExpSolvableFinder;

public function traversingincidenceRowExpFinder "
Author: Frenkel TUD 2010-11
Helper for statesAndVarsExp"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<Integer>>> inTpl;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,list<Integer>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local
      list<Integer> p,pa,res;
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      DAE.Exp e,e1,e2;
      list<Var> varslst;
      Boolean b;
    
    case (((e as DAE.CREF(componentRef = cr),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,true);
      then
        ((e,false,(vars,res)));
    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));
    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));
    /* pre(v) is considered a known variable */
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa)))) then ((e,false,(vars,pa)));
    
    /* delay(e) can be used to break algebraic loops given some solver options */
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "delay"),expLst = {_,_,e1,e2}),(vars,pa))))
      equation
        b = Flags.isSet(Flags.DELAY_BREAK_LOOP) and Expression.expEqual(e1,e2);
      then ((e,not b,(vars,pa)));

    case ((e,(vars,pa))) then ((e,true,(vars,pa)));
  end matchcontinue;
end traversingincidenceRowExpFinder;

protected function incidenceRowExp1
  input list<Var> inVarLst;
  input list<Integer> inIntegerLst;
  input list<Integer> inIntegerLst1;
  input Boolean notinder;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inVarLst,inIntegerLst,inIntegerLst1,notinder)
    local
       list<Var> rest;
       list<Integer> irest,res,vars;
       Integer i,i1;
       Boolean b;
    case ({},{},vars,_) then vars;
    /*If variable x is a state, der(x) is a variable in incidence matrix,
         x is inserted as negative value, since it is needed by debugging and
         index reduction using dummy derivatives */ 
    case (BackendDAE.VAR(varKind = BackendDAE.STATE()) :: rest,i::irest,vars,b)
      equation
        i1 = Util.if_(b,-i,i);
        failure(_ = List.getMemberOnTrue(i1, vars, intEq));
        res = incidenceRowExp1(rest,irest,i1::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.STATE_DER()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.VARIABLE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DISCRETE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (_ :: rest,_::irest,vars,b)
      equation
        res = incidenceRowExp1(rest,irest,vars,b);
      then res;
  end matchcontinue;
end incidenceRowExp1;

public function traversingincidenceRowExpFinderwithInput "
Author: wbraun
Helper for statesAndVarsExp"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,list<Integer>>> inTpl;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,list<Integer>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local
      list<Integer> p,pa,res;
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      DAE.Exp e;
      list<Var> varslst;
    
    case (((e as DAE.CREF(componentRef = cr),(vars,pa))))
      equation
        cr = ComponentReference.makeCrefQual(BackendDAE.partialDerivativeNamePrefix, DAE.T_REAL_DEFAULT, {}, cr);
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1withInput(varslst,p,pa,true);
      then
        ((e,false,(vars,res)));
        
    case (((e as DAE.CREF(componentRef = cr),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1withInput(varslst,p,pa,true);
      then
        ((e,false,(vars,res)));
    
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1withInput(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));

    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa))))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = incidenceRowExp1withInput(varslst,p,pa,false);
      then
        ((e,false,(vars,res)));
    /* pre(v) is considered a known variable */
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {DAE.CREF(componentRef = cr)}),(vars,pa)))) then ((e,false,(vars,pa)));
    
    case ((e,(vars,pa))) then ((e,true,(vars,pa)));
  end matchcontinue;
end traversingincidenceRowExpFinderwithInput;


protected function incidenceRowExp1withInput
  input list<Var> inVarLst;
  input list<Integer> inIntegerLst;
  input list<Integer> inIntegerLst1;
  input Boolean notinder;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inVarLst,inIntegerLst,inIntegerLst1,notinder)
    local
       list<Var> rest;
       list<Integer> irest,res,vars;
       Integer i;
       Boolean b;
    case ({},{},vars,_) then vars;
    /*If variable x is a state, der(x) is a variable in incidence matrix,
         x is inserted as negative value, since it is needed by debugging and
         index reduction using dummy derivatives */ 
    case (BackendDAE.VAR(varKind = BackendDAE.JAC_DIFF_VAR()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.STATE()) :: rest,i::irest,vars,b)
      equation
        failure( true = b);
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;             
    case (BackendDAE.VAR(varKind = BackendDAE.STATE_DER()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.VARIABLE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DISCRETE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE()) :: rest,i::irest,vars,b)
      equation
        failure(_ = List.getMemberOnTrue(i, vars, intEq));
        res = incidenceRowExp1(rest,irest,i::vars,b);
      then res;       
    case (_ :: rest,_::irest,vars,b)
      equation
        res = incidenceRowExp1(rest,irest,vars,b);
      then res;
  end matchcontinue;
end incidenceRowExp1withInput;


public function transposeMatrix
"function: transposeMatrix
  author: PA
  Calculates the transpose of the incidence matrix,
  i.e. which equations each variable is present in."
  input BackendDAE.IncidenceMatrix m;
  output BackendDAE.IncidenceMatrixT mt;
protected
  list<list<Integer>> mlst,mtlst;
algorithm
  mlst := arrayList(m);
  mtlst := transposeMatrix2(mlst);
  mt := listArray(mtlst);
end transposeMatrix;

protected function transposeMatrix2
"function: transposeMatrix2
  author: PA
  Helper function to transposeMatrix"
  input list<list<Integer>> inIntegerLstLst;
  output list<list<Integer>> outIntegerLstLst;
algorithm
  outIntegerLstLst := matchcontinue (inIntegerLstLst)
    local
      Integer neq;
      list<list<Integer>> mt,m;
    case (m)
      equation
        neq = listLength(m);
        mt = transposeMatrix3(m, neq, 0, {});
      then
        mt;
    case (_)
      equation
        print("- BackendDAEUtil.transposeMatrix2 failed\n");
      then
        fail();
  end matchcontinue;
end transposeMatrix2;

protected function transposeMatrix3
"function: transposeMatrix3
  author: PA
  Helper function to transposeMatrix2"
  input list<list<Integer>> inIntegerLstLst1;
  input Integer inInteger2;
  input Integer inInteger3;
  input list<list<Integer>> inIntegerLstLst4;
  output list<list<Integer>> outIntegerLstLst;
algorithm
  outIntegerLstLst := matchcontinue (inIntegerLstLst1,inInteger2,inInteger3,inIntegerLstLst4)
    local
      Integer neq_1,eqno_1,neq,eqno;
      list<list<Integer>> mt_1,m,mt;
      list<Integer> row;
    case (_,0,_,_) then {};
    case (m,neq,eqno,mt)
      equation
        neq_1 = neq - 1;
        eqno_1 = eqno + 1;
        mt_1 = transposeMatrix3(m, neq_1, eqno_1, mt);
        row = transposeRow(m, eqno_1, 1);
      then
        (row :: mt_1);
  end matchcontinue;
end transposeMatrix3;

public function absIncidenceMatrix
"function absIncidenceMatrix
  author: PA
  Applies absolute value to all entries in the incidence matrix.
  This can be used when e.g. der(x) and x are considered the same variable."
  input BackendDAE.IncidenceMatrix m;
  output BackendDAE.IncidenceMatrix res;
  list<list<Integer>> lst,lst_1;
algorithm
  lst := arrayList(m);
  lst_1 := List.mapList(lst, intAbs);
  res := listArray(lst_1);
end absIncidenceMatrix;

public function varsIncidenceMatrix
"function: varsIncidenceMatrix
  author: PA
  Return all variable indices in the incidence
  matrix, i.e. all elements of the matrix."
  input BackendDAE.IncidenceMatrix m;
  output list<Integer> res;
  list<list<Integer>> mlst;
algorithm
  mlst := arrayList(m);
  res := List.flatten(mlst);
end varsIncidenceMatrix;

protected function transposeRow
"function: transposeRow
  author: PA
  Helper function to transposeMatrix2.
  Input: BackendDAE.IncidenceMatrix (eqn => var)
  Input: row number (variable)
  Input: iterator (start with one)
  inputs:  (int list list, int /* row */,int /* iter */)
  outputs:  int list"
  input list<list<Integer>> inIntegerLstLst1;
  input Integer inInteger2;
  input Integer inInteger3;
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inIntegerLstLst1,inInteger2,inInteger3)
    local
      Integer eqn_1,varno,eqn,varno_1,eqnneg;
      list<Integer> res,m;
      list<list<Integer>> ms;
    case ({},_,_) then {};
    case ((m :: ms),varno,eqn)
      equation
        true = listMember(varno, m);
        eqn_1 = eqn + 1;
        res = transposeRow(ms, varno, eqn_1);
      then
        (eqn :: res);
    case ((m :: ms),varno,eqn)
      equation
        varno_1 = 0 - varno "Negative index present, state variable. list_member(varno,m) => false &" ;
        true = listMember(varno_1, m);
        eqnneg = 0 - eqn;
        eqn_1 = eqn + 1;
        res = transposeRow(ms, varno, eqn_1);
      then
        (eqnneg :: res);
    case ((m :: ms),varno,eqn)
      equation
        eqn_1 = eqn + 1 "not present at all" ;
        res = transposeRow(ms, varno, eqn_1);
      then
        res;
    case (_,_,_)
      equation
        print("- BackendDAEUtil.transposeRow failed\n");
      then
        fail();
  end matchcontinue;
end transposeRow;

public function updateIncidenceMatrix
"function: updateIncidenceMatrix
  author: PA
  Takes a daelow and the incidence matrix and its transposed
  represenation and a list of  equation indexes that needs to be updated.
  First the BackendDAE.IncidenceMatrix is updated, i.e. the mapping from equations
  to variables. Then, by collecting all variables in the list of equations
  to update, a list of changed variables are retrieved. This is used to
  update the BackendDAE.IncidenceMatrixT (transpose) mapping from variables to
  equations. The function returns an updated incidence matrix.
  inputs:  (BackendDAE,
            IncidenceMatrix,
            IncidenceMatrixT,
            int list /* list of equations to update */)
  outputs: (IncidenceMatrix, IncidenceMatrixT)"
  input BackendDAE.EqSystem syst;
  input list<Integer> inIntegerLst;
  output BackendDAE.EqSystem osyst;
algorithm
  osyst := matchcontinue (syst,inIntegerLst)
    local
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      list<Integer> eqns;
      BackendDAE.Variables vars;
      EquationArray daeeqns;
      BackendDAE.Matching matching;

    case (BackendDAE.EQSYSTEM(vars,daeeqns,SOME(m),SOME(mt),matching),eqns)
      equation
        (m,mt) = updateIncidenceMatrix1(vars,daeeqns,m,mt,eqns);
      then
        BackendDAE.EQSYSTEM(vars,daeeqns,SOME(m),SOME(mt),matching);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.updateIncididenceMatrix failed"});
      then
        fail();

  end matchcontinue;
end updateIncidenceMatrix;

protected function updateIncidenceMatrix1
  "Helper"
  input BackendDAE.Variables vars;
  input EquationArray daeeqns;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  input list<Integer> inIntegerLst;
  output BackendDAE.IncidenceMatrix outIncidenceMatrix;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT):=
  match (vars,daeeqns,inIncidenceMatrix,inIncidenceMatrixT,inIntegerLst)
    local
      BackendDAE.IncidenceMatrix m,m_1,m_2;
      BackendDAE.IncidenceMatrixT mt,mt_1,mt_2,mt_3;
      Integer e_1,e,abse;
      BackendDAE.Equation eqn;
      list<Integer> row,invars,outvars,eqns,oldvars;

    case (_,_,m,mt,{}) then (m,mt);

    case (_,_,m,mt,(e :: eqns))
      equation
        abse = intAbs(e);
        e_1 = abse - 1;
        eqn = equationNth(daeeqns, e_1);
        (row,_) = incidenceRow(eqn,vars,BackendDAE.NORMAL(),{});
        oldvars = getOldVars(m,abse);
        m_1 = Util.arrayReplaceAtWithFill(abse,row,{},m);
        (_,outvars,invars) = List.intersection1OnTrue(oldvars,row,intEq);
        mt_1 = removeValuefromMatrix(abse,outvars,mt);
        mt_2 = addValuetoMatrix(abse,invars,mt_1);
        (m_2,mt_3) = updateIncidenceMatrix1(vars,daeeqns,m_1,mt_2,eqns);
      then (m_2,mt_3);

  end match;
end updateIncidenceMatrix1;

public function updateIncidenceMatrixScalar
"function: updateIncidenceMatrixScalar
  author: PA
  Takes a daelow and the incidence matrix and its transposed
  represenation and a list of  equation indexes that needs to be updated.
  First the BackendDAE.IncidenceMatrix is updated, i.e. the mapping from equations
  to variables. Then, by collecting all variables in the list of equations
  to update, a list of changed variables are retrieved. This is used to
  update the BackendDAE.IncidenceMatrixT (transpose) mapping from variables to
  equations. The function returns an updated incidence matrix.
  inputs:  (BackendDAE,
            IncidenceMatrix,
            IncidenceMatrixT,
            int list /* list of equations to update */)
  outputs: (IncidenceMatrix, IncidenceMatrixT)"
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndxType;
  input list<Integer> inIntegerLst;
  input array<list<Integer>> iMapEqnIncRow;
  input array<Integer> iMapIncRowEqn;
  output BackendDAE.EqSystem osyst;
  output array<list<Integer>> oMapEqnIncRow;
  output array<Integer> oMapIncRowEqn;
algorithm
  (osyst,oMapEqnIncRow,oMapIncRowEqn) := matchcontinue (syst,inIndxType,inIntegerLst,iMapEqnIncRow,iMapIncRowEqn)
    local
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      Integer oldsize,newsize,oldsize1,newsize1,deltasize;
      list<Integer> eqns;
      BackendDAE.Variables vars;
      EquationArray daeeqns;
      BackendDAE.Matching matching;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;      

    case (BackendDAE.EQSYSTEM(vars,daeeqns,SOME(m),SOME(mt),matching),_,eqns,_,_)
      equation
        // extend the mapping arrays
        oldsize = arrayLength(iMapEqnIncRow);
        newsize = equationArraySize(daeeqns);
        mapEqnIncRow = Util.arrayExpand(newsize-oldsize,iMapEqnIncRow,{});
        oldsize1 = arrayLength(iMapIncRowEqn); 
        newsize1 = equationSize(daeeqns);
        deltasize = newsize1-oldsize1;
        mapIncRowEqn = Util.arrayExpand(deltasize,iMapIncRowEqn,0);
        // extend the incidenceMatrix
        m = Util.arrayExpand(deltasize,m,{});
        mt = Util.arrayExpand(deltasize,mt,{});
        // fill the extended parts first
        (m,mt,mapEqnIncRow,mapIncRowEqn) = updateIncidenceMatrixScalar2(oldsize+1,newsize,oldsize1,vars,daeeqns,m,mt,mapEqnIncRow,mapIncRowEqn,inIndxType);
        // update the old 
        eqns = List.removeOnTrue(oldsize, intLt, eqns);
        (m,mt,mapEqnIncRow,mapIncRowEqn) = updateIncidenceMatrixScalar1(vars,daeeqns,m,mt,eqns,mapEqnIncRow,mapIncRowEqn,inIndxType);
      then
        (BackendDAE.EQSYSTEM(vars,daeeqns,SOME(m),SOME(mt),matching),mapEqnIncRow,mapIncRowEqn);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.updateIncidenceMatrixScalar failed"});
      then
        fail();

  end matchcontinue;
end updateIncidenceMatrixScalar;

protected function updateIncidenceMatrixScalar1
  "Helper"
  input BackendDAE.Variables vars;
  input EquationArray daeeqns;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  input list<Integer> inIntegerLst;
  input array<list<Integer>> iMapEqnIncRow;
  input array<Integer> iMapIncRowEqn;
  input BackendDAE.IndexType inIndxType;
  output BackendDAE.IncidenceMatrix outIncidenceMatrix;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
  output array<list<Integer>> oMapEqnIncRow;
  output array<Integer> oMapIncRowEqn;  
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT,oMapEqnIncRow,oMapIncRowEqn):=
  match (vars,daeeqns,inIncidenceMatrix,inIncidenceMatrixT,inIntegerLst,iMapEqnIncRow,iMapIncRowEqn,inIndxType)
    local
      BackendDAE.IncidenceMatrix m,m_1,m_2;
      BackendDAE.IncidenceMatrixT mt,mt_1,mt_2,mt_3;
      Integer e_1,e,abse,size;
      BackendDAE.Equation eqn;
      list<Integer> row,invars,outvars,eqns,oldvars,scalarindxs;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn; 
      
    case (_,_,m,mt,{},_,_,_) then (m,mt,iMapEqnIncRow,iMapIncRowEqn);

    case (_,_,m,mt,e::eqns,_,_,_)
      equation
        abse = intAbs(e);
        e_1 = abse - 1;
        eqn = equationNth(daeeqns, e_1);
        size = BackendEquation.equationSize(eqn);
        (row,_) = incidenceRow(eqn,vars,inIndxType,{});
        scalarindxs = iMapEqnIncRow[abse];
        oldvars = getOldVars(m,listGet(scalarindxs,1));
        (_,outvars,invars) = List.intersection1OnTrue(oldvars,row,intEq);
        // do the same for each scalar indxs
        m_1 = List.fold1r(scalarindxs,arrayUpdate,row,m);
        mt_1 = List.fold1(scalarindxs,removeValuefromMatrix,outvars,mt);
        mt_2 = List.fold1(scalarindxs,addValuetoMatrix,invars,mt_1);
        (m_2,mt_3,mapEqnIncRow,mapIncRowEqn) = updateIncidenceMatrixScalar1(vars,daeeqns,m_1,mt_2,eqns,iMapEqnIncRow,iMapIncRowEqn,inIndxType);
      then (m_2,mt_3,mapEqnIncRow,mapIncRowEqn);

  end match;
end updateIncidenceMatrixScalar1;

protected function updateIncidenceMatrixScalar2
  "Helper"
  input Integer index;
  input Integer n;
  input Integer size;
  input BackendDAE.Variables vars;
  input EquationArray daeeqns;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  input array<list<Integer>> iMapEqnIncRow;
  input array<Integer> iMapIncRowEqn;
  input BackendDAE.IndexType inIndxType;
  output BackendDAE.IncidenceMatrix outIncidenceMatrix;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
  output array<list<Integer>> oMapEqnIncRow;
  output array<Integer> oMapIncRowEqn;  
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT,oMapEqnIncRow,oMapIncRowEqn):=
  matchcontinue (index,n,size,vars,daeeqns,inIncidenceMatrix,inIncidenceMatrixT,iMapEqnIncRow,iMapIncRowEqn,inIndxType)
    local
      BackendDAE.IncidenceMatrix m;
      BackendDAE.IncidenceMatrixT mt;
      Integer e_1,abse,rowsize,new_size;
      BackendDAE.Equation eqn;
      list<Integer> row,scalarindxs;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn; 
      
    case (_,_,_,_,_,m,mt,_,_,_)
      equation
        false = intGt(index,n);
        abse = intAbs(index);
        e_1 = abse - 1;
        eqn = equationNth(daeeqns, e_1);
        rowsize = BackendEquation.equationSize(eqn);
        (row,_) = incidenceRow(eqn,vars,inIndxType,{});  
        new_size = size+rowsize;      
        scalarindxs = List.intRange2(size+1,new_size);
        mapEqnIncRow = arrayUpdate(iMapEqnIncRow,abse,scalarindxs);
        mapIncRowEqn = List.fold1r(scalarindxs,arrayUpdate,abse,iMapIncRowEqn);
        m = List.fold1r(scalarindxs,arrayUpdate,row,m);
        mt = fillincidenceMatrixT(row,scalarindxs,mt);
        (m,mt,mapEqnIncRow,mapIncRowEqn) = updateIncidenceMatrixScalar2(index+1,n,new_size,vars,daeeqns,m,mt,mapEqnIncRow,mapIncRowEqn,inIndxType);
      then 
        (m,mt,mapEqnIncRow,mapIncRowEqn);
    case (_,_,_,_,_,m,mt,_,_,_)
      then 
        (m,mt,iMapEqnIncRow,iMapIncRowEqn);
  end matchcontinue;
end updateIncidenceMatrixScalar2;

protected function getOldVars
  input array<list<Integer>> m;
  input Integer pos;
  output  list<Integer> oldvars;
algorithm
  oldvars := matchcontinue(m,pos)
  local
    Integer alen;
    case(_,_)
      equation
        alen = arrayLength(m);
        (pos <= alen) = true;
        oldvars = m[pos];
      then
        oldvars;
    case (_,_) then {};
  end matchcontinue;
end getOldVars;

protected function removeValuefromMatrix
"function: removeValuefromMatrix
  author: Frenkel TUD 2011-04"
  input Integer inValue;
  input list<Integer> inIntegerLst;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
algorithm
  outIncidenceMatrixT:=
  matchcontinue (inValue,inIntegerLst,inIncidenceMatrixT)
    local
      BackendDAE.IncidenceMatrixT mt,mt_1,mt_2;
      BackendDAE.IncidenceMatrixElement mlst,mlst1;
      list<Integer> keys;
      Integer k,kabs;
      Integer v,v_1;
    case (_,{},mt) then mt;
    case (v,k :: keys,mt)
      equation
        kabs = intAbs(k);
        mlst = mt[kabs];
        v_1 = Util.if_(intGt(k,0),v,-v);
        mlst1 = List.removeOnTrue(v_1,intEq,mlst);
        mt_1 = arrayUpdate(mt, kabs , mlst1);
        mt_2 = removeValuefromMatrix(v,keys,mt_1);
      then
        mt_2;
    case (v,k :: keys,mt)
      equation
        mt_2 = removeValuefromMatrix(v,keys,mt);
      then
        mt_2;        
    case (_,_,_)
      equation
        print("- BackendDAE.removeValuefromMatrix failed\n");
      then
        fail();
  end matchcontinue;
end removeValuefromMatrix;

protected function addValuetoMatrix
"function: addValuetoMatrix
  author: Frenkel TUD 2011-04"
  input Integer inValue;
  input list<Integer> inIntegerLst;
  input BackendDAE.IncidenceMatrixT inIncidenceMatrixT;
  output BackendDAE.IncidenceMatrixT outIncidenceMatrixT;
algorithm
  outIncidenceMatrixT:=
  matchcontinue (inValue,inIntegerLst,inIncidenceMatrixT)
    local
      BackendDAE.IncidenceMatrixT mt,mt_1,mt_2;
      BackendDAE.IncidenceMatrixElement mlst;
      list<Integer> keys;
      Integer k,kabs;
      Integer v,v_1;
    case (_,{},mt) then mt;
    case (v,k :: keys,mt)
      equation
        kabs = intAbs(k);
        mlst = getOldVars(mt,kabs);
        v_1 = Util.if_(intGt(k,0),v,-v);
        false = listMember(v_1, mlst);
        mt_1 = Util.arrayReplaceAtWithFill(kabs,v_1::mlst,{},mt);
        mt_2 = addValuetoMatrix(v,keys,mt_1);
      then
        mt_2;
    case (v,k :: keys,mt)
      equation
        mt_2 = addValuetoMatrix(v,keys,mt);
      then
        mt_2;        
    case (_,_,_)
      equation
        print("- BackendDAE.addValuetoMatrix failed\n");
      then
        fail();
  end matchcontinue;
end addValuetoMatrix;

public function copyIncidenceMatrix
  input Option<BackendDAE.IncidenceMatrix> inM;
  output Option<BackendDAE.IncidenceMatrix> outM;
algorithm
  outM := match(inM)
  local
    BackendDAE.IncidenceMatrix m,m1;
    case (NONE()) then NONE();
    case (SOME(m)) 
      equation
        m1 = arrayCreate(arrayLength(m),{});
        m1 = Util.arrayCopy(m, m1);
      then SOME(m1);
   end match;
end copyIncidenceMatrix; 

public function getIncidenceMatrixfromOptionForMapEqSystem "function getIncidenceMatrixfromOption"
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
algorithm
  (osyst,_,_) := getIncidenceMatrixfromOption(syst,BackendDAE.NORMAL());
  oshared := shared;
end getIncidenceMatrixfromOptionForMapEqSystem;

public function getIncidenceMatrixfromOption "function getIncidenceMatrixfromOption"
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndxType;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.IncidenceMatrix outM;
  output BackendDAE.IncidenceMatrix outMT;
algorithm
  (osyst,outM,outMT):=
  match (syst,inIndxType)
    local  
      BackendDAE.IncidenceMatrix m,mT;
      BackendDAE.Variables v;
      EquationArray eq;
      BackendDAE.Matching matching;
      BackendDAE.IndexType it;
    case(BackendDAE.EQSYSTEM(v,eq,NONE(),_,matching),it)
      equation
        (m,mT) = incidenceMatrix(syst, it);
      then
        (BackendDAE.EQSYSTEM(v,eq,SOME(m),SOME(mT),matching),m,mT);
    case(BackendDAE.EQSYSTEM(v,eq,SOME(m),NONE(),matching),_)
      equation  
        mT = transposeMatrix(m);
      then
        (BackendDAE.EQSYSTEM(v,eq,SOME(m),SOME(mT),matching),m,mT);
    case(BackendDAE.EQSYSTEM(v,eq,SOME(m),SOME(mT),matching),_)
      then
        (syst,m,mT);
  end match;
end getIncidenceMatrixfromOption;
    
public function getIncidenceMatrix "function getIncidenceMatrix"
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndxType;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.IncidenceMatrix outM;
  output BackendDAE.IncidenceMatrix outMT;
algorithm
  (osyst,outM,outMT):=
  match (syst,inIndxType)
    local  
      BackendDAE.IncidenceMatrix m,mT;
      BackendDAE.Variables v;
      EquationArray eq;
      BackendDAE.Matching matching;
      BackendDAE.IndexType it;
    case(BackendDAE.EQSYSTEM(v,eq,_,_,matching),it)
      equation
        (m,mT) = incidenceMatrix(syst, it);
      then
        (BackendDAE.EQSYSTEM(v,eq,SOME(m),SOME(mT),matching),m,mT);
  end match;
end getIncidenceMatrix;    
    
public function getIncidenceMatrixScalar "function getIncidenceMatrixScalar"
  input BackendDAE.EqSystem syst;
  input BackendDAE.IndexType inIndxType;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.IncidenceMatrix outM;
  output BackendDAE.IncidenceMatrix outMT;
  output array<list<Integer>> outMapEqnIncRow;
  output array<Integer> outMapIncRowEqn;  
algorithm
  (osyst,outM,outMT,outMapEqnIncRow,outMapIncRowEqn):=
  match (syst,inIndxType)
    local  
      BackendDAE.IncidenceMatrix m,mT;
      BackendDAE.Variables v;
      EquationArray eq;
      BackendDAE.Matching matching;
      BackendDAE.IndexType it;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;      
    case(BackendDAE.EQSYSTEM(v,eq,_,_,matching),it)
      equation
        (m,mT,mapEqnIncRow,mapIncRowEqn) = incidenceMatrixScalar(syst, it);
      then
        (BackendDAE.EQSYSTEM(v,eq,SOME(m),SOME(mT),matching),m,mT,mapEqnIncRow,mapIncRowEqn);
  end match;
end getIncidenceMatrixScalar;     
    

protected function traverseStmts "function: traverseStmts
  Author: Frenkel TUD 2012-06
  traverese DAE.Statement without change possibility."
  input list<DAE.Statement> inStmts;
  input FuncExpType func;
  input Type_a iextraArg;
  output Type_a oextraArg;
  partial function FuncExpType 
     input tuple<DAE.Exp,Type_a> arg; 
     output tuple<DAE.Exp,Type_a> oarg; 
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  oextraArg := matchcontinue(inStmts,func,iextraArg)
    local
      DAE.Exp e,e2;
      list<DAE.Exp> expl1;
      DAE.ComponentRef cr;
      list<DAE.Statement> xs,stmts;
      DAE.Type tp;
      DAE.Statement x,ew;
      Boolean b1;
      String id1,str;
      Algorithm.Else algElse;
      Type_a extraArg;
      
    case ({},_,extraArg) then extraArg;
      
    case ((DAE.STMT_ASSIGN(exp1 = e2,exp = e) :: xs),_,extraArg)
      equation
        ((_,extraArg)) = func((e, extraArg));
        ((_,extraArg)) = func((e2, extraArg));
      then 
        traverseStmts(xs, func, extraArg);
        
    case ((DAE.STMT_TUPLE_ASSIGN(expExpLst = expl1, exp = e) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        ((_, extraArg)) = Expression.traverseExpList(expl1,func,extraArg);
      then 
        traverseStmts(xs, func, extraArg);
        
    case ((DAE.STMT_ASSIGN_ARR(componentRef = cr, exp = e) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        ((_, extraArg)) = func((Expression.crefExp(cr), extraArg));
      then 
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_IF(exp=e,statementLst=stmts,else_ = algElse)) :: xs),_,extraArg)
      equation
        extraArg = traverseStmtsElse(algElse,func,extraArg);
        extraArg = traverseStmts(stmts,func,extraArg);
        ((_,extraArg)) = func((e, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_FOR(type_=tp,iterIsArray=b1,iter=id1,range=e,statementLst=stmts)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        cr = ComponentReference.makeCrefIdent(id1, tp, {});
        (stmts,_) = DAEUtil.traverseDAEEquationsStmts(stmts,Expression.traverseSubexpressionsHelper,(Expression.replaceCref,(cr,e)));
        extraArg = traverseStmts(stmts,func,extraArg);
      then 
        traverseStmts(xs, func, extraArg);
    
    case (((x as DAE.STMT_PARFOR(type_=tp,iterIsArray=b1,iter=id1,range=e,statementLst=stmts)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        cr = ComponentReference.makeCrefIdent(id1, tp, {});
        (stmts,_) = DAEUtil.traverseDAEEquationsStmts(stmts,Expression.traverseSubexpressionsHelper,(Expression.replaceCref,(cr,e)));
        extraArg = traverseStmts(stmts,func,extraArg);
      then 
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_WHILE(exp = e,statementLst=stmts)) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts(stmts,func,extraArg);
        ((_, extraArg)) = func((e, extraArg));
      then 
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_WHEN(exp = e,statementLst=stmts,elseWhen=NONE())) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts(stmts,func,extraArg);
        ((_, extraArg)) = func((e, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_WHEN(exp = e,statementLst=stmts,elseWhen=SOME(ew))) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts({ew},func,extraArg);
        extraArg = traverseStmts(stmts,func,extraArg);
        ((_, extraArg)) = func((e, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_ASSERT(cond = e, msg=e2)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        ((_, extraArg)) = func((e2, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_TERMINATE(msg = e)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_REINIT(var = e,value=e2)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
        ((_, extraArg)) = func((e2, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_NORETCALL(exp = e)) :: xs),_,extraArg)
      equation
        ((_, extraArg)) = func((e, extraArg));
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_RETURN(source = _)) :: xs),_,extraArg)
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_BREAK(source = _)) :: xs),_,extraArg)
      then
        traverseStmts(xs, func, extraArg);
        
    // MetaModelica extension. KS
    case (((x as DAE.STMT_FAILURE(body=stmts)) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts(stmts,func,extraArg);
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_TRY(tryBody=stmts)) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts(stmts,func,extraArg);
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_CATCH(catchBody=stmts)) :: xs),_,extraArg)
      equation
        extraArg = traverseStmts(stmts,func,extraArg);
      then
        traverseStmts(xs, func, extraArg);
        
    case (((x as DAE.STMT_THROW(source = _)) :: xs),_,extraArg)
      then
        traverseStmts(xs, func, extraArg);
        
    case ((x :: xs),_,extraArg)
      equation
        str = DAEDump.ppStatementStr(x);
        str = "BackenddAEUtil.traverseStmts not implemented correctly: " +& str;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end matchcontinue;
end traverseStmts;

protected function traverseStmtsElse "
Author: Frenkel TUD 2012-06
Helper function for traverseStmts
"
  input Algorithm.Else inElse;
  input FuncExpType func;
  input Type_a iextraArg;
  output Type_a oextraArg;
  partial function FuncExpType
    input tuple<DAE.Exp,Type_a> arg;
    output tuple<DAE.Exp,Type_a> oarg;
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  oextraArg := match(inElse,func,iextraArg)
  local
    DAE.Exp e;
    list<DAE.Statement> st;
    Algorithm.Else el;
    Type_a extraArg;
  case (DAE.NOELSE(),_,extraArg) then extraArg;
  case (DAE.ELSEIF(e,st,el),_,extraArg)
    equation
      extraArg = traverseStmtsElse(el,func,extraArg);
      ((_,extraArg)) = func((e, extraArg));
    then 
      traverseStmts(st,func,extraArg);
  case(DAE.ELSE(st),_,extraArg)
    then 
      traverseStmts(st,func,extraArg);
end match;
end traverseStmtsElse;    
    
/******************************************************************
 stuff to calculate enhanced Adjacency matrix
  
 The Adjacency matrix descibes the relation between knots and
 knots of a bigraph. Additional information about the solvability
 of a variable are availible.
******************************************************************/    

public function getAdjacencyMatrixEnhancedScalar
"function: getAdjacencyMatrixEnhancedScalar
  author: Frenkel TUD 2012-05
  Calculates the Adjacency matrix, i.e. which variables are present in each equation
  and add some information how the variable occure in the equation(see BackendDAE.BackendDAE.Solvability)."
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  output BackendDAE.AdjacencyMatrixEnhanced outIncidenceMatrix;
  output BackendDAE.AdjacencyMatrixTEnhanced outIncidenceMatrixT;
  output array<list<Integer>> outMapEqnIncRow;
  output array<Integer> outMapIncRowEqn;  
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT,outMapEqnIncRow,outMapIncRowEqn) := 
  matchcontinue (syst, shared)
    local
      BackendDAE.AdjacencyMatrixEnhanced arr;
      BackendDAE.AdjacencyMatrixTEnhanced arrT;
      BackendDAE.Variables vars,kvars;
      BackendDAE.EquationArray eqns;
      list<BackendDAE.WhenClause> wc;
      Integer numberOfEqs,numberofVars;
      array<Integer> rowmark "array to mark if a variable is allready found in the equation, and to mark if it is unsolvable(marked negative) in the equation";
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;
    
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns), BackendDAE.SHARED(knownVars=kvars,eventInfo = BackendDAE.EVENT_INFO(whenClauseLst = wc)))
      equation
        // get the size
        numberOfEqs = equationArraySize(eqns);
        numberofVars = BackendVariable.varsSize(vars);
        // create the array to hold the Adjacency matrix
         arrT = arrayCreate(numberofVars, {});
        // create the array to mark if a variable is allready found in the equation
        rowmark = arrayCreate(numberofVars, 0);
        (arr,arrT,mapEqnIncRow,mapIncRowEqn) = adjacencyMatrixDispatchEnhancedScalar(vars, eqns, wc, {},arrT, 0, numberOfEqs, intLt(0, numberOfEqs),rowmark,kvars ,0,{},{});
      then
        (arr,arrT,mapEqnIncRow,mapIncRowEqn);
    
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.getAdjacencyMatrixEnhanced failed"});
      then
        fail();
  end matchcontinue;
end getAdjacencyMatrixEnhancedScalar;   
    
protected function adjacencyMatrixDispatchEnhancedScalar
"@author: Frenkel TUD 2012-05
  Calculates the adjacency matrix and the transposed 
  adjacency matrix."
  input BackendDAE.Variables vars;
  input BackendDAE.EquationArray eqArr; 
  input list<BackendDAE.WhenClause> wc;
  input list<BackendDAE.AdjacencyMatrixElementEnhanced> inIncidenceArray;
  input BackendDAE.AdjacencyMatrixTEnhanced inIncidenceArrayT;
  input Integer index;
  input Integer numberOfEqs;
  input Boolean stop;
  input array<Integer> rowmark;
  input BackendDAE.Variables kvars;
  input Integer inRowSize;
  input list<list<Integer>> imapEqnIncRow;
  input list<Integer> imapIncRowEqn;  
  output BackendDAE.AdjacencyMatrixEnhanced outIncidenceArray;
  output BackendDAE.AdjacencyMatrixTEnhanced outIncidenceArrayT;
  output array<list<Integer>> omapEqnIncRow;
  output array<Integer> omapIncRowEqn;  
algorithm
  (outIncidenceArray,outIncidenceArrayT,omapEqnIncRow,omapIncRowEqn) := 
    match (vars, eqArr, wc, inIncidenceArray, inIncidenceArrayT, index, numberOfEqs, stop, rowmark, kvars, inRowSize, imapEqnIncRow, imapIncRowEqn)
    local
      BackendDAE.AdjacencyMatrixElementEnhanced row;
      BackendDAE.Equation e;
      list<BackendDAE.AdjacencyMatrixElementEnhanced> iArr;
      BackendDAE.AdjacencyMatrixTEnhanced iArrT;
      Integer i1,rowSize,size;
      list<Integer> mapIncRowEqn,rowindxs;
    
    // index = numberOfEqs (we reach the end)
    case (_, _, _, _, _, _, _,  false, _, _, _, _, _) 
      then 
        (listArray(listReverse(inIncidenceArray)),inIncidenceArrayT,listArray(listReverse(imapEqnIncRow)),listArray(listReverse(imapIncRowEqn)));
    
    // index < numberOfEqs 
    case (_, _, _, iArr, _, _, _, true, _, _, _, _ , _)
      equation
        // get the equation
        e = equationNth(eqArr, index);
        // compute the row
        i1 = index+1;
        (row,size) = adjacencyRowEnhanced(vars, e, wc, i1, rowmark, kvars);
        rowSize = inRowSize + size;
        rowindxs = List.intRange2(inRowSize+1, rowSize);
        mapIncRowEqn = List.consN(size,i1,imapIncRowEqn);        
        // put it in the arrays
        iArr = List.consN(size,row,iArr);        
        iArrT = fillincAdjacencyMatrixTEnhanced(row,rowindxs,inIncidenceArrayT);
        (outIncidenceArray,iArrT,omapEqnIncRow,omapIncRowEqn) = adjacencyMatrixDispatchEnhancedScalar(vars, eqArr, wc, iArr, iArrT, i1, numberOfEqs, intLt(i1, numberOfEqs), rowmark, kvars, rowSize, rowindxs::imapEqnIncRow, mapIncRowEqn);
      then
        (outIncidenceArray,iArrT,omapEqnIncRow,omapIncRowEqn);
  end match;
end adjacencyMatrixDispatchEnhancedScalar;    
    
    
public function getAdjacencyMatrixEnhanced
"function: getAdjacencyMatrixEnhanced
  author: Frenkel TUD 2012-05
  Calculates the Adjacency matrix, i.e. which variables are present in each equation
  and add some information how the variable occure in the equation(see BackendDAE.BackendDAE.Solvability)."
  input BackendDAE.EqSystem syst;
  input BackendDAE.Shared shared;
  output BackendDAE.AdjacencyMatrixEnhanced outIncidenceMatrix;
  output BackendDAE.AdjacencyMatrixTEnhanced outIncidenceMatrixT;
algorithm
  (outIncidenceMatrix,outIncidenceMatrixT) := matchcontinue (syst, shared)
    local
      BackendDAE.AdjacencyMatrixEnhanced arr;
      BackendDAE.AdjacencyMatrixTEnhanced arrT;
      BackendDAE.Variables vars,kvars;
      BackendDAE.EquationArray eqns;
      list<BackendDAE.WhenClause> wc;
      Integer numberOfEqs,numberofVars;
      array<Integer> rowmark "array to mark if a variable is allready found in the equation, and to mark if it is unsolvable(marked negative) in the equation";    
    
    case (BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns), BackendDAE.SHARED(knownVars=kvars,eventInfo = BackendDAE.EVENT_INFO(whenClauseLst = wc)))
      equation
        // get the size
        numberOfEqs = equationArraySize(eqns);
        numberofVars = BackendVariable.varsSize(vars);
        // create the array to hold the Adjacency matrix
        arr = arrayCreate(equationSize(eqns), {});
        arrT = arrayCreate(numberofVars, {});
        // create the array to mark if a variable is allready found in the equation
        rowmark = arrayCreate(numberofVars, 0);
        (arr,arrT) = adjacencyMatrixDispatchEnhanced(vars, eqns, wc, arr,arrT, 0, numberOfEqs, intLt(0, numberOfEqs),rowmark,kvars);
      then
        (arr,arrT);
    
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.getAdjacencyMatrixEnhanced failed"});
      then
        fail();
  end matchcontinue;
end getAdjacencyMatrixEnhanced;    
    
protected function adjacencyMatrixDispatchEnhanced
"@author: Frenkel TUD 2012-05
  Calculates the adjacency matrix and the transposed 
  adjacency matrix."
  input BackendDAE.Variables vars;
  input BackendDAE.EquationArray eqArr; 
  input list<BackendDAE.WhenClause> wc;
  input BackendDAE.AdjacencyMatrixEnhanced inIncidenceArray;
  input BackendDAE.AdjacencyMatrixTEnhanced inIncidenceArrayT;
  input Integer index;
  input Integer numberOfEqs;
  input Boolean stop;
  input array<Integer> rowmark;
  input BackendDAE.Variables kvars;
  output BackendDAE.AdjacencyMatrixEnhanced outIncidenceArray;
  output BackendDAE.AdjacencyMatrixTEnhanced outIncidenceArrayT;
algorithm
  (outIncidenceArray,outIncidenceArrayT) := 
    match (vars, eqArr, wc, inIncidenceArray, inIncidenceArrayT, index, numberOfEqs, stop, rowmark, kvars)
    local
      BackendDAE.AdjacencyMatrixElementEnhanced row;
      BackendDAE.Equation e;
      BackendDAE.AdjacencyMatrixEnhanced iArr;
      BackendDAE.AdjacencyMatrixTEnhanced iArrT;
      Integer i1;
    
    // index = numberOfEqs (we reach the end)
    case (_, _, _, _, _, _, _,  false, _, _) then (inIncidenceArray, inIncidenceArrayT);
    
    // index < numberOfEqs 
    case (_, _, _, _, _, _, _, true, _, _)
      equation
        // get the equation
        e = equationNth(eqArr, index);
        // compute the row
        i1 = index+1;
        (row,_) = adjacencyRowEnhanced(vars, e, wc, i1, rowmark, kvars);
        // put it in the arrays
        iArr = arrayUpdate(inIncidenceArray, i1, row);
        iArrT = fillincAdjacencyMatrixTEnhanced(row,{i1},inIncidenceArrayT);
        (iArr,iArrT) = adjacencyMatrixDispatchEnhanced(vars, eqArr, wc, iArr, iArrT, i1, numberOfEqs, intLt(i1, numberOfEqs), rowmark, kvars);
      then
        (iArr,iArrT);
  end match;
end adjacencyMatrixDispatchEnhanced;

protected function fillincAdjacencyMatrixTEnhanced
"@author: Frenkel TUD 2011-04
  helper for adjacencyMatrixDispatchEnhanced. 
  Inserts the rows in the transposed adiacenca matrix."
  input BackendDAE.AdjacencyMatrixElementEnhanced eqns;
  input list<Integer> eqnsindxs;
  input BackendDAE.AdjacencyMatrixTEnhanced inIncidenceArrayT;
  output BackendDAE.AdjacencyMatrixTEnhanced outIncidenceArrayT;
algorithm
  outIncidenceArrayT := matchcontinue (eqns, eqnsindxs, inIncidenceArrayT)
    local
      BackendDAE.AdjacencyMatrixElementEnhanced row,rest,newrow;
      Integer v,vabs;
      BackendDAE.AdjacencyMatrixTEnhanced mT;
      BackendDAE.Solvability solva;
      list<Integer> eqnsindxs1;
    
    case ({},_,_) then inIncidenceArrayT;
    
    case ((v,solva)::rest,_,_)
      equation
        true = intLt(0, v);
        row = inIncidenceArrayT[v];
        newrow = List.map1(eqnsindxs,Util.makeTuple,solva);
        newrow = listAppend(newrow,row);
        // put it in the array
        mT = arrayUpdate(inIncidenceArrayT, v, newrow);
      then
        fillincAdjacencyMatrixTEnhanced(rest, eqnsindxs, mT);
        
    case ((v,solva)::rest,_,_)
      equation
        false = intLt(0, v);
        vabs = intAbs(v);
        row = inIncidenceArrayT[vabs];
        eqnsindxs1 = List.map(eqnsindxs,intNeg);
        newrow = List.map1(eqnsindxs1,Util.makeTuple,solva);
        // put it in the array
        newrow = listAppend(newrow,row);
        mT = arrayUpdate(inIncidenceArrayT, vabs, newrow);
      then  
        fillincAdjacencyMatrixTEnhanced(rest, eqnsindxs, mT);
    
    case (_,_,_)
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.fillincAdjacencyMatrixTEnhanced failed"});
      then
        fail();
  end matchcontinue;
end fillincAdjacencyMatrixTEnhanced;    
    
protected function adjacencyRowEnhanced
"function: adjacencyRowEnhanced
  author: Frenkel TUD 2012-05
  Helper function to adjacencyMatrixDispatchEnhanced. Calculates the adjacency row
  in the matrix for one equation."
  input BackendDAE.Variables inVariables;
  input BackendDAE.Equation inEquation; 
  input list<BackendDAE.WhenClause> inWhenClause;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.Variables kvars;
  output BackendDAE.AdjacencyMatrixElementEnhanced outRow;
  output Integer size;
algorithm
  (outRow,size) := matchcontinue (inVariables,inEquation,inWhenClause,mark,rowmark,kvars)
    local
      list<Integer> lst,ds;
      BackendDAE.Variables vars;
      DAE.Exp e1,e2,e,expCref,cond;
      list<DAE.Exp> expl;
      DAE.ComponentRef cr;
      BackendDAE.WhenEquation we,elsewe;
      list<BackendDAE.WhenClause> wc;
      String eqnstr;
      DAE.Algorithm alg;
      BackendDAE.AdjacencyMatrixElementEnhanced row;
      list<list<BackendDAE.Equation>> eqnslst;
      list<BackendDAE.Equation> eqns;
      list<DAE.ComponentRef> algoutCrefs;
    
    // EQUATION
    case (vars,BackendDAE.EQUATION(exp = e1,scalar = e2),_,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(e1, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,e1,e2,vars,kvars,mark,rowmark,{});
      then
        (row,1);
    // COMPLEX_EQUATION
    case (vars,BackendDAE.COMPLEX_EQUATION(size=size,left=e1,right=e2),_,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(e1, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,e1,e2,vars,kvars,mark,rowmark,{});
      then
        (row,size);    
    // ARRAY_EQUATION
    case (vars,BackendDAE.ARRAY_EQUATION(dimSize=ds,left=e1,right=e2),_,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(e1, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,e1,e2,vars,kvars,mark,rowmark,{});
        size = List.fold(ds,intMul,1);
      then
        (row,size);        
    
    // SOLVED_EQUATION
    case (vars,BackendDAE.SOLVED_EQUATION(componentRef = cr,exp = e),_,_,_,_)
      equation
        expCref = Expression.crefExp(cr);
        lst = adjacencyRowExpEnhanced(expCref, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e, vars, lst,(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,expCref,e,vars,kvars,mark,rowmark,{});
      then
        (row,1);
    // RESIDUAL_EQUATION
    case (vars,BackendDAE.RESIDUAL_EQUATION(exp = e),_,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(e, vars, {},(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,e,DAE.RCONST(0.0),vars,kvars,mark,rowmark,{});
      then
        (row,1);    
    // WHEN_EQUATION
    case (vars,BackendDAE.WHEN_EQUATION(whenEquation = we as BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=NONE())),wc,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(cond, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        // mark all negative because the when condition cannot used to solve a variable 
        _ = List.fold1(lst,markNegativ,rowmark,mark);
        e1 = Expression.crefExp(cr);
        lst = adjacencyRowExpEnhanced(e1, vars, lst,(mark,rowmark));
        row = adjacencyRowEnhanced1(lst,e1,e2,vars,kvars,mark,rowmark,{});
      then
        (row,1);
    case (vars,BackendDAE.WHEN_EQUATION(size=size,whenEquation = we as BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=SOME(elsewe))),wc,_,_,_)
      equation
        lst = adjacencyRowExpEnhanced(cond, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        // mark all negative because the when condition cannot used to solve a variable 
        _ = List.fold1(lst,markNegativ,rowmark,mark);
        e1 = Expression.crefExp(cr);
        lst = adjacencyRowExpEnhanced(e1, vars, lst,(mark,rowmark));
        lst = adjacencyRowWhenEnhanced(vars,elsewe,wc,mark,rowmark,kvars,lst);
        row = adjacencyRowEnhanced1(lst,e1,e2,vars,kvars,mark,rowmark,{});
      then
        (row,size);        
    
    // ALGORITHM For now assume that algorithm will be solvable for 
    // output variables. Mark this as solved and input variables as unsolvable:
    case (vars,BackendDAE.ALGORITHM(size=size,alg=alg),_,_,_,_)
      equation
        // get outputs
        algoutCrefs = CheckModel.algorithmOutputs(alg);
        // mark outputs as solved
        row = adjacencyRowAlgorithmOutputs(algoutCrefs,vars,mark,rowmark,{});
        // get inputs
        expl = Algorithm.getAllExps(alg);
        // mark inputs as unsolvable
        ((_,(_,_,_,row))) = Expression.traverseExpList(expl, adjacencyRowAlgorithmInputs, (vars,mark,rowmark,row));
      then 
        (row,size);
            
    // if Equation
    // TODO : how to handle this?
    // Proposal:
    // mark all vars in conditions as unsolvable
    // vars occure in all branches: check how they are occure
    // vars occure not in all branches: mark as unsolvable 
    case(vars,BackendDAE.IF_EQUATION(conditions=expl,eqnstrue=eqnslst,eqnsfalse=eqns),_,_,_,_)
      equation
        print("Warning: BackendDAEUtil.adjacencyRowEnhanced does not handle if-equations propper!\n");

      then
        ({},1);            
            
    else
      equation
        eqnstr = BackendDump.equationStr(inEquation);
        eqnstr = stringAppendList({"BackendDAE.adjacencyRowEnhancedd failed for eqn:\n",eqnstr,"\n"});
        Error.addMessage(Error.INTERNAL_ERROR,{eqnstr});
      then
        fail();
  end matchcontinue;
end adjacencyRowEnhanced;    

protected function adjacencyRowAlgorithmOutputs
"function: adjacencyRowAlgorithmOutputs
  author: Frenkel TUD 10-2012
  Helper function to adjacencyRowEnhanced. Mark all algorithm outputs
  as solved."
  input list<DAE.ComponentRef> algOutputs;
  input BackendDAE.Variables inVariables;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.AdjacencyMatrixElementEnhanced iRow;
  output BackendDAE.AdjacencyMatrixElementEnhanced outRow;
algorithm
  outRow := matchcontinue(algOutputs,inVariables,mark,rowmark,iRow)
    local
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> rest;
      list<Integer> vindx;
      BackendDAE.AdjacencyMatrixElementEnhanced row;
    case ({},_,_,_,_) then iRow;
    case (cr::rest,_,_,_,_)
      equation
        (_,vindx) = BackendVariable.getVar(cr,inVariables);
        row = adjacencyRowAlgorithmOutputs1(vindx,mark,rowmark,iRow);
      then
        adjacencyRowAlgorithmOutputs(rest,inVariables,mark,rowmark,row); 
  end matchcontinue;
end adjacencyRowAlgorithmOutputs;

protected function adjacencyRowAlgorithmOutputs1
"function: adjacencyRowAlgorithmOutputs
  author: Frenkel TUD 10-2012
  Helper function to adjacencyRowEnhanced. Mark all algorithm outputs
  as solved."
  input list<Integer> vindx;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.AdjacencyMatrixElementEnhanced iRow;
  output BackendDAE.AdjacencyMatrixElementEnhanced outRow;
algorithm
  outRow := matchcontinue(vindx,mark,rowmark,iRow)
    local
      Integer i;
      list<Integer> rest;
    case ({},_,_,_) then iRow;
    case (i::rest,_,_,_)
      equation
        _ = arrayUpdate(rowmark,i,mark);
      then
        adjacencyRowAlgorithmOutputs1(rest,mark,rowmark,(i,BackendDAE.SOLVABILITY_SOLVED())::iRow); 
  end matchcontinue;
end adjacencyRowAlgorithmOutputs1;

protected function adjacencyRowAlgorithmInputs
"function: adjacencyRowAlgorithmInputs
  author: Frenkel TUD 10-2012
  Helper function to adjacencyRowEnhanced. Mark all algorithm inputs
  as unsolvable."
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer,array<Integer>,BackendDAE.AdjacencyMatrixElementEnhanced>> iTpl;
  output tuple<DAE.Exp,tuple<BackendDAE.Variables,Integer,array<Integer>,BackendDAE.AdjacencyMatrixElementEnhanced>> oTpl;
algorithm
  oTpl := matchcontinue(iTpl)
    local
      DAE.Exp e;
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      Integer mark;
      array<Integer>rowmark;
      BackendDAE.AdjacencyMatrixElementEnhanced row;
      list<Integer> vindx;
    case ((e as DAE.CREF(componentRef=cr),(vars,mark,rowmark,row)))
      equation
        (_,vindx) = BackendVariable.getVar(cr,vars);
        row = adjacencyRowAlgorithmInputs1(vindx,mark,rowmark,row);
      then
        ((e,(vars,mark,rowmark,row)));
    else
      then 
        iTpl;
  end matchcontinue;
end adjacencyRowAlgorithmInputs;

protected function adjacencyRowAlgorithmInputs1
"function: adjacencyRowAlgorithmInputs1
  author: Frenkel TUD 10-2012
  Helper function to adjacencyRowEnhanced. Mark all algorithm inputs
  as unsolvable."
  input list<Integer> vindx;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.AdjacencyMatrixElementEnhanced iRow;
  output BackendDAE.AdjacencyMatrixElementEnhanced outRow;
algorithm
  outRow := matchcontinue(vindx,mark,rowmark,iRow)
    local
      Integer i;
      list<Integer> rest;
    case ({},_,_,_) then iRow;
    case (i::rest,_,_,_)
      equation
        // not allready handled
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,-mark);
      then
        adjacencyRowAlgorithmInputs1(rest,mark,rowmark,(i,BackendDAE.SOLVABILITY_UNSOLVABLE())::iRow); 
    case (i::rest,_,_,_)
      equation
        // not allready handled
        true = intEq(intAbs(rowmark[i]),mark);
      then
        adjacencyRowAlgorithmInputs1(rest,mark,rowmark,iRow); 
  end matchcontinue;
end adjacencyRowAlgorithmInputs1;

protected function adjacencyRowWhenEnhanced
"function: adjacencyRowWhenEnhanced
  author: Frenkel TUD
  Helper function to adjacencyMatrixDispatchEnhanced. Calculates the adjacency row
  in the matrix for one equation."
  input BackendDAE.Variables inVariables;
  input BackendDAE.WhenEquation inEquation; 
  input list<BackendDAE.WhenClause> inWhenClause;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.Variables kvars;
  input list<Integer> iRow;
  output list<Integer> outRow;
algorithm
  outRow := match (inVariables,inEquation,inWhenClause,mark,rowmark,kvars,iRow)
    local
      list<Integer> lst;
      BackendDAE.Variables vars;
      DAE.Exp e1,e2,cond;
      DAE.ComponentRef cr;
      BackendDAE.WhenEquation elsewe;
      list<WhenClause> wc;

    case (vars,BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=NONE()),wc,_,_,_,_)
      equation
        // mark all negative because the when condition cannot used to solve a variable 
        lst = adjacencyRowExpEnhanced(cond, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        _ = List.fold1(lst,markNegativ,rowmark,mark);
        lst = listAppend(lst,iRow);
        e1 = Expression.crefExp(cr);
        lst = adjacencyRowExpEnhanced(e1, vars, lst,(mark,rowmark));
      then
        lst; 
    case (vars,BackendDAE.WHEN_EQ(condition=cond,left=cr,right=e2,elsewhenPart=SOME(elsewe)),wc,_,_,_,_)
      equation
        // mark all negative because the when condition cannot used to solve a variable 
        lst = adjacencyRowExpEnhanced(cond, vars, {},(mark,rowmark));
        lst = adjacencyRowExpEnhanced(e2, vars, lst,(mark,rowmark));
        _ = List.fold1(lst,markNegativ,rowmark,mark);
        lst = listAppend(lst,iRow);
        e1 = Expression.crefExp(cr);
        lst = adjacencyRowExpEnhanced(e1, vars, lst,(mark,rowmark));
        lst = adjacencyRowWhenEnhanced(vars,elsewe,wc,mark,rowmark,kvars,lst);
      then
        lst;  
      
  end match;
end adjacencyRowWhenEnhanced;

protected function markNegativ
"function: markNegativ
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced. Update the array
  with a negative entry in indx."
  input Integer indx;
  input array<Integer> rowmark;
  input Integer mark;
  output Integer oMark;
algorithm
  _ := arrayUpdate(rowmark,indx,-mark); 
  oMark := mark; 
end markNegativ;    
    
protected function adjacencyRowEnhanced1
"function: adjacencyRowEnhanced1
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced. Calculates the 
  solvability of the variables."
  input list<Integer> lst;
  input DAE.Exp e1;
  input DAE.Exp e2;
  input BackendDAE.Variables vars;
  input BackendDAE.Variables kvars;
  input Integer mark;
  input array<Integer> rowmark;
  input BackendDAE.AdjacencyMatrixElementEnhanced inRow;    
  output BackendDAE.AdjacencyMatrixElementEnhanced outRow;    
algorithm
  outRow := matchcontinue(lst,e1,e2,vars,kvars,mark,rowmark,inRow)
    local
      Integer r;
      list<Integer> rest;
      DAE.Exp de;
      DAE.ComponentRef cr,cr1;
      BackendDAE.Solvability solvab;
      list<DAE.ComponentRef> crlst;
      Absyn.Path path,path1;
      list<DAE.Exp> explst;
    case({},_,_,_,_,_,_,_) then inRow;
    case(r::rest,_,_,_,_,_,_,_)
      equation
        // if r negativ then unsolvable
        true = intLt(r,0);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_UNSOLVABLE())::inRow);
    case(r::rest,DAE.CALL(path= Absyn.IDENT("der"),expLst={DAE.CREF(componentRef = cr)}),_,_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1,varKind=BackendDAE.STATE()) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasDerCref(e2,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,_,DAE.CALL(path= Absyn.IDENT("der"),expLst={DAE.CREF(componentRef = cr)}),_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1,varKind=BackendDAE.STATE()) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasDerCref(e1,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,DAE.CREF(componentRef=cr),_,_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e2,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,DAE.LUNARY(operator=DAE.NOT(_),exp=DAE.CREF(componentRef=cr)),_,_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e2,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,_,DAE.CREF(componentRef=cr),_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e1,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,_,DAE.LUNARY(operator=DAE.NOT(_),exp=DAE.CREF(componentRef=cr)),_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e1,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,DAE.CREF(componentRef=cr),_,_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefPrefixOf(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e2,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);        
    case(r::rest,_,DAE.CREF(componentRef=cr),_,_,_,_,_)
      equation
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = ComponentReference.crefPrefixOf(cr, cr1);
        false = Expression.expHasCrefNoPreorDer(e1,cr);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);
    case(r::rest,DAE.CALL(path=path,expLst=explst,attr=DAE.CALL_ATTR(ty= DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(path1)))),_,_,_,_,_,_)
      equation
        true = Absyn.pathEqual(path,path1);
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = expCrefLstHasCref(explst,cr1);
        false = Expression.expHasCrefNoPreorDer(e2,cr1);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);        
    case(r::rest,_,DAE.CALL(path=path,expLst=explst,attr=DAE.CALL_ATTR(ty= DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(path1)))),_,_,_,_,_)
      equation
        true = Absyn.pathEqual(path,path1);
        // if not negatet rowmark then  
        false = intEq(rowmark[r],-mark);
        // solved?
        BackendDAE.VAR(varName=cr1) = BackendVariable.getVarAt(vars, r);
        true = expCrefLstHasCref(explst,cr1);
        false = Expression.expHasCrefNoPreorDer(e1,cr1);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_SOLVED())::inRow);        
    case(r::rest,_,_,_,_,_,_,_)
      equation
        // if not negatet rowmark then linear or nonlinear 
        false = intEq(rowmark[r],-mark);
        // de/dvar 
        BackendDAE.VAR(varName=cr,varKind=BackendDAE.STATE()) = BackendVariable.getVarAt(vars, r);
        cr1 = ComponentReference.crefPrefixDer(cr);
        de = Expression.crefExp(cr);
        ((de,_)) = Expression.replaceExp(Expression.expSub(e1,e2), DAE.CALL(Absyn.IDENT("der"),{de},DAE.callAttrBuiltinReal), Expression.crefExp(cr1));
        de = Derive.differentiateExp(de, cr1, true , NONE());
        (de,_) = ExpressionSimplify.simplify(de);
        ((_,crlst)) = Expression.traverseExp(de, Expression.traversingComponentRefFinder, {});
        solvab = adjacencyRowEnhanced2(cr1,de,crlst,vars,kvars);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,solvab)::inRow);
    case(r::rest,_,_,_,_,_,_,_)
      equation
        // if not negatet rowmark then linear or nonlinear 
        false = intEq(rowmark[r],-mark);
        // de/dvar 
        BackendDAE.VAR(varName=cr) = BackendVariable.getVarAt(vars, r);
        de = Derive.differentiateExp(Expression.expSub(e1,e2), cr, true , NONE());
        (de,_) = ExpressionSimplify.simplify(de);
        ((_,crlst)) = Expression.traverseExp(de, Expression.traversingComponentRefFinder, {});
        solvab = adjacencyRowEnhanced2(cr,de,crlst,vars,kvars);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,solvab)::inRow);
    case(r::rest,_,_,_,_,_,_,_)
      equation
        // if negatet rowmark then unsolvable
        //true = intEq(rowmark[r],-mark);
      then
        adjacencyRowEnhanced1(rest,e1,e2,vars,kvars,mark,rowmark,(r,BackendDAE.SOLVABILITY_UNSOLVABLE())::inRow);
  end matchcontinue;
end adjacencyRowEnhanced1;

protected function expCrefLstHasCref
  input list<DAE.Exp> iExpLst;
  input DAE.ComponentRef inCr;
  output Boolean outB;
algorithm
  outB := matchcontinue(iExpLst,inCr)
    local
      DAE.ComponentRef cr;
      list<DAE.Exp> rest;
      Boolean b;
    case ({},_) then false;
    case (DAE.CREF(componentRef=cr)::rest,_)
      equation
        b = ComponentReference.crefEqualNoStringCompare(cr,inCr);
        b = Debug.bcallret2(not b, expCrefLstHasCref, rest, inCr, b);
      then
        b;
    else
      then
        false;        
  end matchcontinue;
end expCrefLstHasCref;

protected function adjacencyRowEnhanced2
"function: adjacencyRowEnhanced1
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced. Calculates the 
  solvability of the variables."
  input DAE.ComponentRef cr;
  input DAE.Exp e;
  input list<DAE.ComponentRef> crlst;
  input BackendDAE.Variables vars;
  input BackendDAE.Variables kvars;
  output BackendDAE.Solvability oSolvab;    
algorithm
  oSolvab := matchcontinue(cr,e,crlst,vars,kvars)
    local
      Boolean b,b1,b2;
    case(_,_,{},_,_)
      equation
        b = Expression.isConstOne(e) or Expression.isConstMinusOne(e);
      then 
        Util.if_(b,BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_CONST());
    case(_,_,_,_,_)
      equation
        true = List.isMemberOnTrue(cr,crlst,ComponentReference.crefEqualNoStringCompare);
      then
        BackendDAE.SOLVABILITY_NONLINEAR();
    case(_,_,_,_,_)
      equation
        b1 = containAnyVar(crlst,kvars);
        b2 = containAnyVar(crlst,vars);
      then 
        adjacencyRowEnhanced3(b1,b2,cr,e,crlst,vars,kvars);
  end matchcontinue;
end adjacencyRowEnhanced2; 

protected function adjacencyRowEnhanced3
"function: adjacencyRowEnhanced1
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced. Calculates the 
  solvability of the variables."
  input Boolean b1;
  input Boolean b2;
  input DAE.ComponentRef cr;
  input DAE.Exp e;
  input list<DAE.ComponentRef> crlst;
  input BackendDAE.Variables vars;
  input BackendDAE.Variables kvars;
  output BackendDAE.Solvability oSolvab;    
algorithm
  oSolvab := matchcontinue(b1,b2,cr,e,crlst,vars,kvars)
    local
      Boolean b,b_1;
      DAE.Exp e1;
    case(true,true,_,_,_,_,_)
      equation
        ((e1,_)) = Expression.traverseExp(e, replaceVartraverser, kvars);
        (e1,_) = ExpressionSimplify.simplify(e1);
        b = not Expression.isZero(e1);
      then 
       BackendDAE.SOLVABILITY_TIMEVARYING(b);
    case(false,_,_,_,_,_,_)
      equation
        b = not Expression.isZero(e);
      then 
        BackendDAE.SOLVABILITY_TIMEVARYING(b);
    case(true,_,_,_,_,_,_)
      equation
        ((e1,_)) = Expression.traverseExp(e, replaceVartraverser, kvars);
        (e1,_) = ExpressionSimplify.simplify(e1);
        b = not Expression.isZero(e1);
        b_1 = Expression.isConst(e1);
      then 
       Util.if_(b_1,BackendDAE.SOLVABILITY_PARAMETER(b),BackendDAE.SOLVABILITY_TIMEVARYING(b));
    case(_,_,_,_,_,_,_)
      equation
        b = not Expression.isZero(e);
      then 
        BackendDAE.SOLVABILITY_TIMEVARYING(b);
/*    case(_,_,_,_,_,_,_)
      equation
        BackendDump.debugStrCrefStrExpStr(("Warning cannot calculate solvabilty for",cr," in ",e,"\n"));
      then 
        BackendDAE.SOLVABILITY_TIMEVARYING(true);
*/  end matchcontinue;
end adjacencyRowEnhanced3;    

protected function replaceVartraverser
"function: replaceVartraverser
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced3. Traverser
  to replace variables(parameters) with there bind expression."
  input tuple<DAE.Exp, BackendDAE.Variables > inExp;
  output tuple<DAE.Exp, BackendDAE.Variables > outExp;
algorithm 
  outExp := matchcontinue(inExp)
    local
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      BackendDAE.Var v;
      DAE.Exp e;
    
    case((e as DAE.CREF(componentRef=cr),vars))
      equation
        (v::_,_) = BackendVariable.getVar(cr,vars);
        e = BackendVariable.varBindExp(v);
        ((e,_)) = Expression.traverseExp(e, replaceVartraverser, vars);
      then
        ((e, vars ));
    
    case _ then inExp;
    
  end matchcontinue;
end replaceVartraverser;
    
protected function adjacencyRowExpEnhanced
"function: adjacencyRowExpEnhanced
  author: Frenkel TUD 2012-05
  Helper function to adjacencyRowEnhanced, investigates expressions for
  variables, returning variable indexes, and mark the solvability."
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  input list<Integer> inRow;
  input tuple<Integer,array<Integer>> inTpl;  
  output list<Integer> outRow;
algorithm
  ((_,(_,_,_,outRow))) := Expression.traverseExpTopDown(inExp, traversingadjacencyRowExpSolvableEnhancedFinder, (inVariables,false,inTpl,inRow));
end adjacencyRowExpEnhanced;

public function traversingadjacencyRowExpSolvableEnhancedFinder "
Author: Frenkel TUD 2010-11
  Helper for adjacencyRowExpEnhanced"
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,Boolean,tuple<Integer,array<Integer>>,list<Integer>>> inTpl "(exp,(variables,unsolvable,(mark,rowmark),row))";
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,Boolean,tuple<Integer,array<Integer>>,list<Integer>>> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
  local
      list<Integer> p,pa,res;
      DAE.ComponentRef cr;
      BackendDAE.Variables vars;
      DAE.Exp e,e1,e2,e3;
      list<DAE.Exp> elst;
      list<BackendDAE.Var> varslst;
      Boolean b,bs;
      Integer mark;
      array<Integer> rowmark;
      BinaryTree.BinTree bt;
    case ((e as DAE.LUNARY(exp = e1),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa)));
    case ((e as DAE.LBINARY(exp1 = e1,exp2=e2),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e2, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa)));        
    case ((e as DAE.RELATION(exp1 = e1,exp2=e2),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e2, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa)));        
    case ((e as DAE.IFEXP(expCond=e3,expThen = e1,expElse = e2),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,bs,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e2, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,bs,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e3, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        // mark all vars which are not in alle branches unsolvable
        ((_,bt)) = Expression.traverseExpTopDown(e,getIfExpBranchVarOccurency,BinaryTree.emptyBinTree);
        ((_,(_,_,_,_))) = Expression.traverseExp(e1,markBranchVars,(mark,rowmark,vars,bt));
        ((_,(_,_,_,_))) = Expression.traverseExp(e2,markBranchVars,(mark,rowmark,vars,bt));
      then
        ((e,false,(vars,bs,(mark,rowmark),pa)));
    case ((e as DAE.RANGE(start = e1,step=NONE(),stop=e2),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e2, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa))); 
    case ((e as DAE.RANGE(start = e1,step=SOME(e3),stop=e2),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e2, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e3, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa))); 
    case ((e as DAE.ASUB(exp = e1,sub=elst),(vars,bs,(mark,rowmark),pa)))
      equation
        ((_,(vars,_,_,pa))) = Expression.traverseExpTopDown(e1, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,bs,(mark,rowmark),pa));
        ((_,(vars,_,_,pa))) = Expression.traverseExpListTopDown(elst, traversingadjacencyRowExpSolvableEnhancedFinder, (vars,true,(mark,rowmark),pa));
      then ((e,false,(vars,bs,(mark,rowmark),pa)));
    case (((e as DAE.CREF(componentRef = cr),(vars,bs,(mark,rowmark),pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = adjacencyRowExpEnhanced1(varslst,p,pa,true,mark,rowmark,bs);
      then
        ((e,false,(vars,bs,(mark,rowmark),res)));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,bs,(mark,rowmark),pa))))
      equation
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = adjacencyRowExpEnhanced1(varslst,p,pa,false,mark,rowmark,bs);
      then
        ((e,false,(vars,bs,(mark,rowmark),res)));
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),(vars,bs,(mark,rowmark),pa))))
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        (varslst,p) = BackendVariable.getVar(cr, vars);
        res = adjacencyRowExpEnhanced1(varslst,p,pa,false,mark,rowmark,bs);
      then
        ((e,false,(vars,bs,(mark,rowmark),res)));
    // pre(v) is considered a known variable 
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {DAE.CREF(componentRef = cr)}),(vars,bs,(mark,rowmark),pa)))) then ((e,false,(vars,bs,(mark,rowmark),pa)));
    // delay(e) can be used to break algebraic loops given some solver options 
    case (((e as DAE.CALL(path = Absyn.IDENT(name = "delay"),expLst = {_,_,e1,e2}),(vars,bs,(mark,rowmark),pa))))
      equation
        b = Flags.isSet(Flags.DELAY_BREAK_LOOP) and Expression.expEqual(e1,e2);
      then ((e,not b,(vars,bs,(mark,rowmark),pa)));
    case ((e,(vars,bs,(mark,rowmark),pa))) then ((e,true,(vars,bs,(mark,rowmark),pa)));
  end matchcontinue;
end traversingadjacencyRowExpSolvableEnhancedFinder;    

protected function markBranchVars
"Author: Frenkel TUD 2012-09
  mark all vars of a if expression which are not in all branches as unsolvable"
  input tuple<DAE.Exp, tuple<Integer,array<Integer>,BackendDAE.Variables,BinaryTree.BinTree>> inTuple;
  output tuple<DAE.Exp, tuple<Integer,array<Integer>,BackendDAE.Variables,BinaryTree.BinTree>> outTuple;
algorithm
  outTuple := matchcontinue(inTuple)
    local
      DAE.Exp e;
      BackendDAE.Variables vars;
      DAE.ComponentRef cr;
      BinaryTree.BinTree bt;
      list<Integer> ilst;
      Integer mark;
      array<Integer> rowmark;
      list<BackendDAE.Var> backendVars;
    
    // special case for time, it is never part of the equation system  
    case ((e as DAE.CREF(componentRef = DAE.CREF_IDENT(ident="time")),(mark,rowmark,vars,bt)))
      then ((e, (mark,rowmark,vars,bt)));
        
    // case for functionpointers    
    case ((e as DAE.CREF(ty=DAE.T_FUNCTION_REFERENCE_FUNC(builtin=_)),(mark,rowmark,vars,bt)))
      then
        ((e, (mark,rowmark,vars,bt)));

    // mark if not in bt
    case ((e as DAE.CREF(componentRef = cr),(mark,rowmark,vars,bt)))
      equation
         (backendVars,ilst) = BackendVariable.getVar(cr, vars);
         markBranchVars1(backendVars,ilst,mark,rowmark,bt);
      then
        ((e, (mark,rowmark,vars,bt)));
   
    case _ then inTuple;
  end matchcontinue;
end markBranchVars;

protected function markBranchVars1
"Author: Frenkel TUD 2012-09
  Helper for markBranchVars"
  input list<BackendDAE.Var> varlst;
  input list<Integer> iIlst;
  input Integer mark;
  input array<Integer> rowmark;
  input BinaryTree.BinTree bt;
algorithm
  _ := matchcontinue(varlst,iIlst,mark,rowmark,bt)
    local
      DAE.ComponentRef cr;
     list<BackendDAE.Var> vlst;
     Integer i;
     list<Integer> ilst;
    case({},_,_,_,_) then ();
    case(BackendDAE.VAR(varName=cr)::vlst,_::ilst,_,_,_)
      equation
        _ = BinaryTree.treeGet(bt,cr);
        markBranchVars1(vlst,ilst,mark,rowmark,bt);
      then
        ();
    case(_::vlst,i::ilst,_,_,_)
      equation
        _ = arrayUpdate(rowmark,i,-mark);
        markBranchVars1(vlst,ilst,mark,rowmark,bt);
      then
        ();
  end matchcontinue;  
end markBranchVars1;

protected function getIfExpBranchVarOccurency
"Author: Frenkel TUD 2012-09
  Helper for getIfExpBranchVarOccurency"
  input tuple<DAE.Exp, BinaryTree.BinTree> inTpl "(exp,allbranchvars)";
  output tuple<DAE.Exp, Boolean, BinaryTree.BinTree> outTpl;  
algorithm
  outTpl := match(inTpl)
    local
      DAE.ComponentRef cr;
      DAE.Exp e,e1,e2;
      BinaryTree.BinTree bt,bt_then,bt_else;
      Boolean b;
      list<DAE.Exp> elst;
    case ((e as DAE.IFEXP(expThen = e1,expElse = e2),bt))
      equation
        ((_,bt_then)) = Expression.traverseExpTopDown(e1,getIfExpBranchVarOccurency,BinaryTree.emptyBinTree);
        ((_,bt_else)) = Expression.traverseExpTopDown(e2,getIfExpBranchVarOccurency,BinaryTree.emptyBinTree);
        bt = BinaryTree.binTreeintersection(bt_then,bt_else,bt);
      then
        ((e,false,bt));
    // skip relations,ranges,asubs
    case ((e as DAE.LUNARY(exp = _),bt))
      then ((e,false,bt));
    case ((e as DAE.LBINARY(exp1 = _),bt))
      then ((e,false,bt));      
    case ((e as DAE.RELATION(exp1 = _),bt))
      then ((e,false,bt));       
    case ((e as DAE.RANGE(start = _),bt))
      then ((e,false,bt)); 
    case ((e as DAE.RANGE(start = _),bt))
      then ((e,false,bt)); 
    case ((e as DAE.ASUB(exp = e1,sub=elst),bt))
      equation
        ((_,bt)) = Expression.traverseExpTopDown(e1, getIfExpBranchVarOccurency, bt);
      then ((e,false,bt));
    // add crefs
    case ((e as DAE.CREF(componentRef = cr),bt))
      equation
        bt = BinaryTree.treeAdd(bt,cr,0);
      then
        ((e,false,bt));
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),bt))
      equation
        bt = BinaryTree.treeAdd(bt,cr,0);
      then
        ((e,false,bt));
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst = {DAE.CREF(componentRef = cr)}),bt))
      equation
        bt = BinaryTree.treeAdd(bt,cr,0);
      then
        ((e,false,bt));
    // pre(v) is considered a known variable 
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {DAE.CREF(componentRef = cr)}),bt)) then ((e,false,bt));
    // delay(e) can be used to break algebraic loops given some solver options 
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "delay"),expLst = {_,_,e1,e2}),bt))
      equation
        b = Flags.isSet(Flags.DELAY_BREAK_LOOP) and Expression.expEqual(e1,e2);
      then ((e,not b,bt));
    case ((e,bt)) then ((e,true,bt));        
  end match;
end getIfExpBranchVarOccurency;

protected function adjacencyRowExpEnhanced1
"function: adjacencyRowExpEnhanced1
  author: Frenkel TUD 2012-05
  Helper function to traversingadjacencyRowExpSolvableEnhancedFinder, fill the variable indexes
  int the list and update the array to mark the variables."
  input list<BackendDAE.Var> inVarLst;
  input list<Integer> inIntegerLst;
  input list<Integer> vars;
  input Boolean notinder;
  input Integer mark;
  input array<Integer> rowmark;
  input Boolean unsolvable;  
  output list<Integer> outIntegerLst;
algorithm
  outIntegerLst := matchcontinue (inVarLst,inIntegerLst,vars,notinder,mark,rowmark,unsolvable)
    local
       list<BackendDAE.Var> rest;
       list<Integer> irest,res;
       Integer i,i1;
       Boolean b,b1;
    case ({},{},_,_,_,_,_) then vars;
    /*If variable x is a state, der(x) is a variable in incidence matrix,
         x is inserted as negative value, since it is needed by debugging and
         index reduction using dummy derivatives */ 
    case (BackendDAE.VAR(varKind = BackendDAE.STATE()) :: rest,i::irest,_,false,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;         
    case (BackendDAE.VAR(varKind = BackendDAE.STATE()) :: rest,i::irest,_,true,_,_,_)
      equation
        i1 = -i;
        failure(_ = List.getMemberOnTrue(i1, vars, intEq));
        res = adjacencyRowExpEnhanced1(rest,irest,i1::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.STATE_DER()) :: rest,i::irest,_,_,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.STATE_DER()) :: rest,i::irest,_,_,_,_,true)
      equation
        b = intEq(rowmark[i],mark);
        b1 = intEq(rowmark[i],-mark);
        b = b or b1;
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = List.consOnTrue(not b, i, vars);
        res = adjacencyRowExpEnhanced1(rest,irest,res,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.VARIABLE()) :: rest,i::irest,_,_,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.VARIABLE()) :: rest,i::irest,_,_,_,_,true)
      equation
        b = intEq(rowmark[i],mark);
        b1 = intEq(rowmark[i],-mark);
        b = b or b1;
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = List.consOnTrue(not b, i, vars);
        res = adjacencyRowExpEnhanced1(rest,irest,res,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DISCRETE()) :: rest,i::irest,_,_,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DISCRETE()) :: rest,i::irest,_,_,_,_,true)
      equation
        b = intEq(rowmark[i],mark);
        b1 = intEq(rowmark[i],-mark);
        b = b or b1;
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = List.consOnTrue(not b, i, vars);
        res = adjacencyRowExpEnhanced1(rest,irest,res,notinder,mark,rowmark,unsolvable);
      then res;        
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER()) :: rest,i::irest,_,_,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_DER()) :: rest,i::irest,_,_,_,_,true)
      equation
        b = intEq(rowmark[i],mark);
        b1 = intEq(rowmark[i],-mark);
        b = b or b1;
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = List.consOnTrue(not b, i, vars);
        res = adjacencyRowExpEnhanced1(rest,irest,res,notinder,mark,rowmark,unsolvable);
      then res;      
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE()) :: rest,i::irest,_,_,_,_,_)
      equation
        false = intEq(intAbs(rowmark[i]),mark);
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = adjacencyRowExpEnhanced1(rest,irest,i::vars,notinder,mark,rowmark,unsolvable);
      then res;
    case (BackendDAE.VAR(varKind = BackendDAE.DUMMY_STATE()) :: rest,i::irest,_,_,_,_,true)
      equation
        b = intEq(rowmark[i],mark);
        b1 = intEq(rowmark[i],-mark);
        b = b or b1;
        _ = arrayUpdate(rowmark,i,Util.if_(unsolvable,-mark,mark));
        res = List.consOnTrue(not b, i, vars);
        res = adjacencyRowExpEnhanced1(rest,irest,res,notinder,mark,rowmark,unsolvable);
      then res;       
    case (_ :: rest,_::irest,_,_,_,_,_)
      equation
        res = adjacencyRowExpEnhanced1(rest,irest,vars,notinder,mark,rowmark,unsolvable);
      then res;
  end matchcontinue;
end adjacencyRowExpEnhanced1;    
    
public function solvabilityWights
"function: solvabilityWights
  author: Frenkel TUD 2012-05,
  return a integer for the solvability, this function is used
  to calculade wights for variables "
  input BackendDAE.Solvability solva;
  output Integer i;
algorithm
  i := match(solva)
    case BackendDAE.SOLVABILITY_SOLVED() then 1;
    case BackendDAE.SOLVABILITY_CONSTONE() then 2;
    case BackendDAE.SOLVABILITY_CONST() then 5;
    case BackendDAE.SOLVABILITY_PARAMETER(b=false) then 0;
    case BackendDAE.SOLVABILITY_PARAMETER(b=true) then 50;
    case BackendDAE.SOLVABILITY_TIMEVARYING(b=false) then 0;
    case BackendDAE.SOLVABILITY_TIMEVARYING(b=true) then 100;
    case BackendDAE.SOLVABILITY_NONLINEAR() then 500;
    case BackendDAE.SOLVABILITY_UNSOLVABLE() then 1000;
  end match;
end solvabilityWights;   

public function solvabilityCMP
"function: solvabilityCMP
  author: Frenkel TUD 2012-05,
  function to compare solvabilities in the way solvabilityA < solvabilityB with
  solved < constone < const < parameter < timevarying < nonlinear < unsolvable."
  input BackendDAE.Solvability sa;
  input BackendDAE.Solvability sb;
  output Boolean b;
algorithm
  b := matchcontinue(sa,sb)
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_SOLVED()) then false;
    case (_,BackendDAE.SOLVABILITY_SOLVED()) then true;
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_CONSTONE()) then false;
    case (BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_CONSTONE()) then false;
    case (_,BackendDAE.SOLVABILITY_CONSTONE()) then true;
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_CONST()) then false;
    case (BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_CONST()) then false;
    case (BackendDAE.SOLVABILITY_CONST(),BackendDAE.SOLVABILITY_CONST()) then false;
    case (_,BackendDAE.SOLVABILITY_CONST()) then true;
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_PARAMETER(b=_)) then false;
    case (BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_PARAMETER(b=_)) then false;
    case (BackendDAE.SOLVABILITY_CONST(),BackendDAE.SOLVABILITY_PARAMETER(b=_)) then false;
    case (BackendDAE.SOLVABILITY_PARAMETER(b=_),BackendDAE.SOLVABILITY_PARAMETER(b=_)) then false;
    case (_,BackendDAE.SOLVABILITY_PARAMETER(b=_)) then true;
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then false;
    case (BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then false;
    case (BackendDAE.SOLVABILITY_CONST(),BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then false;
    case (BackendDAE.SOLVABILITY_PARAMETER(b=_),BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then false;
    case (BackendDAE.SOLVABILITY_TIMEVARYING(b=_),BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then false;
    case (_,BackendDAE.SOLVABILITY_TIMEVARYING(b=_)) then true;
    case (BackendDAE.SOLVABILITY_SOLVED(),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (BackendDAE.SOLVABILITY_CONSTONE(),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (BackendDAE.SOLVABILITY_CONST(),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (BackendDAE.SOLVABILITY_PARAMETER(b=_),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (BackendDAE.SOLVABILITY_TIMEVARYING(b=_),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (BackendDAE.SOLVABILITY_NONLINEAR(),BackendDAE.SOLVABILITY_NONLINEAR()) then false;
    case (_,BackendDAE.SOLVABILITY_NONLINEAR()) then true;
    case (BackendDAE.SOLVABILITY_UNSOLVABLE(),BackendDAE.SOLVABILITY_UNSOLVABLE()) then false;
    case (BackendDAE.SOLVABILITY_UNSOLVABLE(),_) then true;
  end matchcontinue;
end solvabilityCMP;  
    
/*************************************
 jacobian stuff
 ************************************/

public function calculateJacobian "function: calculateJacobian
  This function takes an array of equations and the variables of the equation
  and calculates the jacobian of the equations."
  input BackendDAE.Variables inVariables;
  input EquationArray inEquationArray;
  input BackendDAE.IncidenceMatrix inIncidenceMatrix;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  output Option<list<tuple<Integer, Integer, BackendDAE.Equation>>> outTplIntegerIntegerEquationLstOption;
algorithm
  outTplIntegerIntegerEquationLstOption:=
  matchcontinue (inVariables,inEquationArray,inIncidenceMatrix,differentiateIfExp,iShared)
    local
      list<BackendDAE.Equation> eqn_lst;
      list<tuple<Integer, Integer, BackendDAE.Equation>> jac;
      BackendDAE.Variables vars;
      EquationArray eqns;
      BackendDAE.IncidenceMatrix m;
    case (vars,eqns,m,_,_)
      equation
        eqn_lst = equationList(eqns);
        jac = calculateJacobianRows(eqn_lst,vars,m,1,1,differentiateIfExp,iShared,varsInEqn,{});
      then
        SOME(jac);
    else then NONE();  /* no analytic jacobian available */
  end matchcontinue;
end calculateJacobian;

public function calculateJacobianEnhanced "function: calculateJacobianEnhanced
  This function takes an array of equations and the variables of the equation
  and calculates the jacobian of the equations."
  input BackendDAE.Variables vars;
  input EquationArray eqns;
  input BackendDAE.AdjacencyMatrixEnhanced m;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  output Option<list<tuple<Integer, Integer, BackendDAE.Equation>>> outTplIntegerIntegerEquationLstOption;
algorithm
  outTplIntegerIntegerEquationLstOption:=
  matchcontinue (vars,eqns,m,differentiateIfExp,iShared)
    local
      list<BackendDAE.Equation> eqn_lst;
      list<tuple<Integer, Integer, BackendDAE.Equation>> jac;
    case (_,_,_,_,_)
      equation
        eqn_lst = equationList(eqns);
        jac = calculateJacobianRows(eqn_lst,vars,m,1,1,differentiateIfExp,iShared,varsInEqnEnhanced,{});
      then
        SOME(jac);
    else then NONE();  /* no analytic jacobian available */
  end matchcontinue;
end calculateJacobianEnhanced;

public function traverseequationToResidualForm "function: traverseequationToResidualForm
  author: Frenkel TUD 2010-11
  helper for calculateJacobian"
  input tuple<BackendDAE.Equation, list<BackendDAE.Equation>> inTpl;
  output tuple<BackendDAE.Equation, list<BackendDAE.Equation>> outTpl;
algorithm
  outTpl := matchcontinue (inTpl)
    local
      list<BackendDAE.Equation> eqns;
      BackendDAE.Equation eqn,reqn;
    case ((eqn,eqns))
      equation
        reqn = BackendEquation.equationToResidualForm(eqn);
      then
        ((eqn,reqn::eqns));
    case (inTpl) then inTpl;
  end matchcontinue;
end traverseequationToResidualForm;

public function traverseEquationToScalarResidualForm "function traverseEquationToScalarResidualForm
  author: Frenkel TUD 2010-11
  helper for calculateJacobian"
  input tuple<BackendDAE.Equation, list<BackendDAE.Equation>> inTpl;
  output tuple<BackendDAE.Equation, list<BackendDAE.Equation>> outTpl;
algorithm
  outTpl := matchcontinue (inTpl)
    local
      list<BackendDAE.Equation> eqns,reqn;
      BackendDAE.Equation eqn;
    case ((eqn,eqns)) equation
      reqn = BackendEquation.equationToScalarResidualForm(eqn);
      eqns = listAppend(reqn,eqns);
    then ((eqn,eqns));
    
    case _
    then inTpl;
  end matchcontinue;
end traverseEquationToScalarResidualForm;

protected function calculateJacobianRows "function: calculateJacobianRows
  author: PA
  This function takes a list of Equations and a set of variables and
  calculates the jacobian expression for each variable over each equations,
  returned in a sparse matrix representation.
  For example, the equation on index e1: 3ax+5yz+ zz  given the
  variables {x,y,z} on index x1,y1,z1 gives
  {(e1,x1,3a), (e1,y1,5z), (e1,z1,5y+2z)}"
  replaceable type Type_a subtypeof Any;
  input list<BackendDAE.Equation> inEquationLst;
  input BackendDAE.Variables vars;
  input Type_a m;
  input Integer eqn_indx;
  input Integer scalar_eqn_indx;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  input varsInEqnFunc varsInEqn;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> iAcc;
  output list<tuple<Integer, Integer, BackendDAE.Equation>> outLst;
  partial function varsInEqnFunc
    input Type_a m;
    input Integer indx;
    output list<Integer> outIntegerLst;
  end varsInEqnFunc;  
algorithm
  outLst:= match (inEquationLst,vars,m,eqn_indx,scalar_eqn_indx,differentiateIfExp,iShared,varsInEqn,iAcc)
    local
      list<tuple<Integer, Integer, BackendDAE.Equation>> res;
      BackendDAE.Equation eqn;
      list<BackendDAE.Equation> eqns;
      Integer size;
    case ({},_,_,_,_,_,_,_,_) then listReverse(iAcc);
    case (eqn :: eqns,_,_,_,_,_,_,_,_)
      equation
        (res,size) = calculateJacobianRow(eqn, vars,  m, eqn_indx, scalar_eqn_indx,differentiateIfExp,iShared,varsInEqn,iAcc);
      then
        calculateJacobianRows(eqns, vars, m, eqn_indx + 1, scalar_eqn_indx + size,differentiateIfExp,iShared,varsInEqn,res);
  end match;
end calculateJacobianRows;

protected function calculateJacobianRow "function: calculateJacobianRow
  author: PA
  Calculates the jacobian for one equation. See calculateJacobianRows.
  inputs:  (Equation,
              BackendDAE.Variables,
              IncidenceMatrix,
              IncidenceMatrixT,
              int /* eqn index */)
  outputs: ((int  int  Equation) list option)"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.Equation inEquation;
  input BackendDAE.Variables vars;
  input Type_a m;
  input Integer eqn_indx;
  input Integer scalar_eqn_indx;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  input varsInEqnFunc fvarsInEqn;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> iAcc;
  output list<tuple<Integer, Integer, BackendDAE.Equation>> outLst;
  output Integer size;
  partial function varsInEqnFunc
    input Type_a m;
    input Integer indx;
    output list<Integer> outIntegerLst;
  end varsInEqnFunc;
algorithm
  (outLst,size):=  match (inEquation,vars,m,eqn_indx,scalar_eqn_indx,differentiateIfExp,iShared,fvarsInEqn,iAcc)
    local
      list<Integer> var_indxs,var_indxs_1,ds;
      list<Option<Integer>> ad;
      list<tuple<Integer, Integer, BackendDAE.Equation>> eqns;
      DAE.Exp e,e1,e2;
      list<DAE.Exp> expl;
      Expression.Type t;
      list<list<DAE.Subscript>> subslst;
      DAE.ElementSource source;
      DAE.ComponentRef cr;
      String str;
    // residual equations
    case (BackendDAE.EQUATION(exp = e1,scalar=e2,source=source),_,_,_,_,_,_,_,_)
      equation
        var_indxs = fvarsInEqn(m, eqn_indx);
        var_indxs_1 = List.unionOnTrue(var_indxs, {}, intEq) "Remove duplicates and get in correct order: ascending index" ;
        var_indxs_1 = List.sort(var_indxs_1,intGt);
        eqns = calculateJacobianRow2(Expression.expSub(e1,e2), vars, scalar_eqn_indx, var_indxs_1,differentiateIfExp,iShared,source,iAcc);
      then
        (eqns,1);
    // residual equations
    case (BackendDAE.RESIDUAL_EQUATION(exp = e,source=source),_,_,_,_,_,_,_,_)
      equation
        var_indxs = fvarsInEqn(m, eqn_indx);
        var_indxs_1 = List.unionOnTrue(var_indxs, {}, intEq) "Remove duplicates and get in correct order: ascending index" ;
        var_indxs_1 = List.sort(var_indxs_1,intGt);
        eqns = calculateJacobianRow2(e, vars, scalar_eqn_indx, var_indxs_1,differentiateIfExp,iShared,source,iAcc);
      then
        (eqns,1);
    // solved equations
    case (BackendDAE.SOLVED_EQUATION(componentRef=cr,exp=e2,source=source),_,_,_,_,_,_,_,_)
      equation
        e1 = Expression.crefExp(cr);
        var_indxs = fvarsInEqn(m, eqn_indx);
        var_indxs_1 = List.unionOnTrue(var_indxs, {}, intEq) "Remove duplicates and get in correct order: ascending index" ;
        var_indxs_1 = List.sort(var_indxs_1,intGt);
        eqns = calculateJacobianRow2(Expression.expSub(e1,e2), vars, scalar_eqn_indx, var_indxs_1,differentiateIfExp,iShared,source,iAcc);
      then
        (eqns,1);        
    // array equations
    case (BackendDAE.ARRAY_EQUATION(dimSize=ds,left=e1,right=e2,source=source),_,_,_,_,_,_,_,_)
      equation
        t = Expression.typeof(e1);
        e = Expression.expSub(e1,e2);
        ((e,_)) = extendArrExp((e,(NONE(),false)));
        ad = List.map(ds,Util.makeOption);
        subslst = arrayDimensionsToRange(ad);
        subslst = rangesToSubscripts(subslst);
        expl = List.map1r(subslst,Expression.applyExpSubscripts,e);
        var_indxs = fvarsInEqn(m, eqn_indx);
        var_indxs_1 = List.unionOnTrue(var_indxs, {}, intEq) "Remove duplicates and get in correct order: acsending index";
        var_indxs_1 = List.sort(var_indxs_1,intGt);
        eqns = calculateJacobianRowLst(expl, vars, scalar_eqn_indx, var_indxs_1,differentiateIfExp,iShared,source,iAcc);
        size = List.fold(ds,intMul,1);
      then
        (eqns,size);
    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        str = BackendDump.dumpEqnsStr({inEquation});
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.calculateJacobianRow failed on " +& str +& "\n");
      then
        fail();
  end match;
end calculateJacobianRow;

public function getArrayEquationSub"function: getArrayEquationSub
  author: Frenkel TUD
  helper for calculateJacobianRow"
  input Integer Index;
  input list<Option<Integer>> inAD;
  input list<tuple<Integer,list<list<DAE.Subscript>>>> inList;
  output list<DAE.Subscript> outSubs;
  output list<tuple<Integer,list<list<DAE.Subscript>>>> outList;
algorithm
  (outSubs,outList) := 
  matchcontinue (Index,inAD,inList)
    local
      Integer i,ie;
      list<Option<Integer>> ad;
      list<DAE.Subscript> subs,subs1;
      list<list<DAE.Subscript>> subslst,subslst1;
      list<tuple<Integer,list<list<DAE.Subscript>>>> rest,entrylst;
      tuple<Integer,list<list<DAE.Subscript>>> entry;
    // new entry  
    case (i,ad,{})
      equation
        subslst = arrayDimensionsToRange(ad);
        (subs::subslst1) = rangesToSubscripts(subslst);
      then
        (subs,{(i,subslst1)});
    // found last entry
    case (i,ad,(entry as (ie,{subs}))::rest)
      equation
        true = intEq(i,ie);
      then   
        (subs,rest);
    // found entry
    case (i,ad,(entry as (ie,subs::subslst))::rest)
      equation
        true = intEq(i,ie);
      then   
        (subs,(ie,subslst)::rest);
    // next entry  
    case (i,ad,(entry as (ie,subslst))::rest)
      equation
        false = intEq(i,ie);
        (subs1,entrylst) = getArrayEquationSub(i,ad,rest);
      then   
        (subs1,entry::entrylst);
    case (_,_,_)
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.getArrayEquationSub failed");
      then
        fail();
  end matchcontinue;
end getArrayEquationSub;

public function arrayDimensionsToRange "
Author: Frenkel TUD 2010-05"
  input list<Option<Integer>> idims;
  output list<list<DAE.Subscript>> outRangelist;
algorithm
  outRangelist := match(idims)
  local 
    Integer i;
    list<list<DAE.Subscript>> rangelist;
    list<Integer> range;
    list<DAE.Subscript> subs;
    list<Option<Integer>> dims;
    
    case({}) then {};
    case(NONE()::dims) equation
      rangelist = arrayDimensionsToRange(dims);
    then {}::rangelist;
    case(SOME(i)::dims) equation
      range = List.intRange(i);
      subs = rangesToSubscript(range);
      rangelist = arrayDimensionsToRange(dims);
    then subs::rangelist;
  end match;
end arrayDimensionsToRange;


protected function makeResidualEqn "function: makeResidualEqn
  author: PA
  Transforms an expression into a residual equation"
  input DAE.Exp inExp;
  output BackendDAE.Equation outEquation;
algorithm
  outEquation := matchcontinue (inExp)
    local DAE.Exp e;
    case (e) then BackendDAE.RESIDUAL_EQUATION(e,DAE.emptyElementSource);
  end matchcontinue;
end makeResidualEqn;

protected function calculateJacobianRowLst "function: calculateJacobianRowLst
  author: Frenkel TUD 2012-06
  calls calculateJacobianRow2 for a list of DAE.Exp"
  input list<DAE.Exp> inExps;
  input BackendDAE.Variables vars;
  input Integer eqn_indx;
  input list<Integer> inIntegerLst;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  input DAE.ElementSource source;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> iAcc;
  output list<tuple<Integer, Integer, BackendDAE.Equation>> outLst;
algorithm
  outLst := match(inExps,vars,eqn_indx,inIntegerLst,differentiateIfExp,iShared,source,iAcc)
    local
      DAE.Exp e;
      list<DAE.Exp> elst;
      list<tuple<Integer, Integer, BackendDAE.Equation>> eqns;
    case ({},_,_,_,_,_,_,_) then iAcc;
    case (e::elst,_,_,_,_,_,_,_)
      equation
        eqns = calculateJacobianRow2(e,vars,eqn_indx,inIntegerLst,differentiateIfExp,iShared,source,iAcc);
      then
        calculateJacobianRowLst(elst,vars,eqn_indx+1,inIntegerLst,differentiateIfExp,iShared,source,eqns);
  end match;
end calculateJacobianRowLst;

protected function calculateJacobianRow2 "function: calculateJacobianRow2
  author: PA
  Helper function to calculateJacobianRow
  Differentiates expression for each variable cref.
  inputs: (DAE.Exp,
             BackendDAE.Variables,
             int, /* equation index */
             int list) /* var indexes */
  outputs: ((int int Equation) list option)"
  input DAE.Exp inExp;
  input BackendDAE.Variables vars;
  input Integer eqn_indx;
  input list<Integer> inIntegerLst;
  input Boolean differentiateIfExp "If true, allow differentiation of if-expressions";
  input BackendDAE.Shared iShared;
  input DAE.ElementSource source;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> iAcc;
  output list<tuple<Integer, Integer, BackendDAE.Equation>> outLst;
algorithm
  outLst := matchcontinue (inExp,vars,eqn_indx,inIntegerLst,differentiateIfExp,iShared,source,iAcc)
    local
      DAE.Exp e,e_1,e_2,dcrexp;
      Var v;
      DAE.ComponentRef cr,dcr;
      list<tuple<Integer, Integer, BackendDAE.Equation>> es;
      Integer vindx;
      list<Integer> vindxs;
      String str;
      DAE.FunctionTree ft;
    case (_,_,_,{},_,_,_,_) then iAcc;
    case (_,_,_,vindx :: vindxs,_,_,_,_)
      equation
        v = BackendVariable.getVarAt(vars, vindx);
        cr = BackendVariable.varCref(v);
        true = BackendVariable.isStateVar(v);
        dcr = ComponentReference.crefPrefixDer(cr);
        dcrexp = Expression.crefExp(cr);
        dcrexp = DAE.CALL(Absyn.IDENT("der"),{dcrexp},DAE.callAttrBuiltinReal);
        ((e,_)) = Expression.replaceExp(inExp, dcrexp, Expression.crefExp(dcr));
        ft = getFunctions(iShared);
        e_1 = Derive.differentiateExp(e, dcr, differentiateIfExp , SOME(ft));
        (e_2,_) = ExpressionSimplify.simplify(e_1);
        es = calculateJacobianRow3(eqn_indx,vindx,e_2,source,iAcc);
      then
        calculateJacobianRow2(inExp, vars, eqn_indx, vindxs, differentiateIfExp,iShared,source,es);   
    case (_,_,_,vindx :: vindxs,_,_,_,_)
      equation
        v = BackendVariable.getVarAt(vars, vindx);
        cr = BackendVariable.varCref(v);
        ft = getFunctions(iShared);
        e_1 = Derive.differentiateExp(inExp, cr, differentiateIfExp, SOME(ft));
        (e_2,_) = ExpressionSimplify.simplify(e_1);
        es = calculateJacobianRow3(eqn_indx,vindx,e_2,source,iAcc);
      then
        calculateJacobianRow2(inExp, vars, eqn_indx, vindxs, differentiateIfExp,iShared,source,es);
    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        str = ExpressionDump.printExpStr(inExp);
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.calculateJacobianRow2 failed on " +& str +& "\n");
      then
        fail();        
  end matchcontinue;
end calculateJacobianRow2;

protected function calculateJacobianRow3
  input Integer eqn_indx;
  input Integer vindx;
  input DAE.Exp inExp;
  input DAE.ElementSource source;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> iAcc;
  output list<tuple<Integer, Integer, BackendDAE.Equation>> outLst;
algorithm
  outLst := matchcontinue(eqn_indx,vindx,inExp,source,iAcc)
    case (_,_,_,_,_)
      equation
        true = Expression.isZero(inExp);
      then
        iAcc;
    else
      (eqn_indx,vindx,BackendDAE.RESIDUAL_EQUATION(inExp,source)) :: iAcc;
  end matchcontinue;
end calculateJacobianRow3;

public function analyzeJacobian "function: analyzeJacobian
  author: PA
  Analyze the jacobian to find out if the jacobian of system of equations
  can be solved at compiletime or runtime or if it is a nonlinear system
  of equations."
  input BackendDAE.Variables vars;
  input EquationArray eqns;
  input Option<list<tuple<Integer, Integer, BackendDAE.Equation>>> inTplIntegerIntegerEquationLstOption;
  output BackendDAE.JacobianType outJacobianType;
algorithm
  outJacobianType:=
  matchcontinue (vars,eqns,inTplIntegerIntegerEquationLstOption)
    local
      list<tuple<Integer, Integer, BackendDAE.Equation>> jac;
      Boolean b,b1;
    case (_,_,SOME(jac))
      equation
        true = jacobianConstant(jac);
        true = rhsConstant(vars,eqns);
      then
        BackendDAE.JAC_CONSTANT();
    case (_,_,SOME(jac))
      equation
        b = jacobianNonlinear(vars, jac);
        // check also if variables occure in if expressions
        ((_,false)) = Debug.bcallret3(not b,traverseBackendDAEExpsEqnsWithStop,eqns,varsNotInRelations,(vars,true),(vars,false));
      then
        BackendDAE.JAC_NONLINEAR();
    case (_,_,SOME(jac)) then BackendDAE.JAC_TIME_VARYING();
    case (_,_,NONE()) then BackendDAE.JAC_NO_ANALYTIC();
  end matchcontinue;
end analyzeJacobian;

protected function varsNotInRelations "function varsNotInRelations
  author: Frenkel TUD 2012-09"
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,Boolean>> inTplExpTypeA;
  output tuple<DAE.Exp,Boolean, tuple<BackendDAE.Variables,Boolean>> outTplExpBoolTypeA;
algorithm
  outTplExpBoolTypeA := match(inTplExpTypeA)
    local
      DAE.Exp cond,t,f,e,e1;
      BackendVarTransform.VariableReplacements repl;
      BackendDAE.Variables vars;
      Boolean b,b1;
      Absyn.Path path;
      list<DAE.Exp> expLst;
      Option<DAE.FunctionTree> funcs;
    case ((DAE.IFEXP(cond,t,f),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(cond, getEqnsysRhsExp2, (vars,b));
        ((t,(_,b))) = Expression.traverseExpTopDown(t, varsNotInRelations, (vars,b));
        ((f,(_,b))) = Expression.traverseExpTopDown(f, varsNotInRelations, (vars,b));
      then
        ((DAE.IFEXP(cond,t,f),false,(vars,b)));
    case ((e as DAE.CALL(path = path as Absyn.IDENT(name = "der")),(vars,b)))
      then
        ((e,true,(vars,b)));         
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "pre")),(vars,b)))
      then
        ((e,false,(vars,b)));         
    case ((e as DAE.CALL(expLst=expLst),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpListTopDown(expLst, getEqnsysRhsExp2, (vars,b));
      then
        ((e,false,(vars,b)));
    case ((e as DAE.LBINARY(exp1=_),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(e, getEqnsysRhsExp2, (vars,b));
      then
        ((e,false,(vars,b)));
    case ((e as DAE.LUNARY(exp=_),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(e, getEqnsysRhsExp2, (vars,b));
      then
        ((e,false,(vars,b)));
    case ((e as DAE.RELATION(exp1=_),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(e, getEqnsysRhsExp2, (vars,b));
      then
        ((e,false,(vars,b)));
    case ((e as DAE.ASUB(exp=e1,sub=expLst),(vars,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(e1, varsNotInRelations, (vars,b));
        ((_,(_,b))) = Debug.bcallret3(b,Expression.traverseExpListTopDown,expLst, getEqnsysRhsExp2, (vars,b),(expLst,(vars,b)));
      then
        ((e,false,(vars,b)));        
    case ((e,(vars,b))) then ((e,b,(vars,b)));
  end match;
end varsNotInRelations;

protected function rhsConstant "function: rhsConstant
  author: PA
  Determines if the right hand sides of an equation system,
  represented as a BackendDAE, is constant."
  input BackendDAE.Variables vars; 
  input EquationArray eqns;
  output Boolean outBoolean;
algorithm
  outBoolean:=
  matchcontinue (vars,eqns)
    local
      Boolean res;
    case (_,_)
      equation
        0 = equationSize(eqns);
      then
        true;
    case (_,_)
      equation
        ((_,res)) = BackendEquation.traverseBackendDAEEqnsWithStop(eqns,rhsConstant2,(vars,true));
      then
        res;
  end matchcontinue;
end rhsConstant;

protected function rhsConstant2 "function: rhsConstant2
  author: PA
  Helper function to rhsConstant, traverses equation list."
  input tuple<BackendDAE.Equation, tuple<BackendDAE.Variables,Boolean>> inTpl;
  output tuple<BackendDAE.Equation, Boolean, tuple<BackendDAE.Variables,Boolean>> outTpl;
algorithm
  outTpl := matchcontinue (inTpl)
    local
      DAE.Exp new_exp,rhs_exp,e1,e2,e;
      Boolean b,res;
      BackendDAE.Equation eqn;
      BackendDAE.Variables vars;

    // check rhs for for EQUATION nodes.
    case ((eqn as BackendDAE.EQUATION(exp = e1,scalar = e2),(vars,b)))
      equation
        new_exp = Expression.expSub(e1, e2);
        rhs_exp = getEqnsysRhsExp(new_exp, vars,NONE());
        res = Expression.isConst(rhs_exp);
      then
        ((eqn,res,(vars,b and res)));
    // check rhs for for ARRAY_EQUATION nodes. check rhs for for RESIDUAL_EQUATION nodes.
    case ((eqn as BackendDAE.ARRAY_EQUATION(left=e1,right=e2),(vars,b)))
      equation
        new_exp = Expression.expSub(e1, e2);
        rhs_exp = getEqnsysRhsExp(new_exp, vars,NONE());
        res = Expression.isConst(rhs_exp);
      then
        ((eqn,res,(vars,b and res)));

    case ((eqn as BackendDAE.COMPLEX_EQUATION(left=e1,right=e2),(vars,b)))
      equation
        new_exp = Expression.expSub(e1, e2);
        rhs_exp = getEqnsysRhsExp(new_exp, vars,NONE());
        res = Expression.isConst(rhs_exp);
      then
        ((eqn,res,(vars,b and res)));

    case ((eqn as BackendDAE.RESIDUAL_EQUATION(exp = e),(vars,b))) /* check rhs for for RESIDUAL_EQUATION nodes. */
      equation
        rhs_exp = getEqnsysRhsExp(e, vars,NONE());
        res = Expression.isConst(rhs_exp);
      then
        ((eqn,res,(vars,b and res)));
    case ((eqn,(vars,_))) then ((eqn,false,(vars,false)));
  end matchcontinue;
end rhsConstant2;

protected function freeFromAnyVar "function: freeFromAnyVar
  author: PA
  Helper function to rhsConstant2
  returns true if expression does not contain
  anyof the variables passed as argument."
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp,inVariables)
    local
      DAE.Exp e;
      list<DAE.ComponentRef> crefs;
      list<Boolean> b_lst;
      Boolean res,res_1;
      BackendDAE.Variables vars;

    case (e,_)
      equation
        {} = Expression.extractCrefsFromExp(e) "Special case for expressions with no variables" ;
      then
        true;
    case (e,vars)
      equation
        crefs = Expression.extractCrefsFromExp(e);
        b_lst = List.map2(crefs, BackendVariable.existsVar, vars, false);
        res = Util.boolOrList(b_lst);
        res_1 = boolNot(res);
      then
        res_1;
    case (_,_) then true;
  end matchcontinue;
end freeFromAnyVar;

protected function jacobianConstant "function: jacobianConstant
  author: PA
  Checks if jacobian is constant, i.e. all expressions in each equation are constant."
  input list<tuple<Integer, Integer, BackendDAE.Equation>> inTplIntegerIntegerEquationLst;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inTplIntegerIntegerEquationLst)
    local
      DAE.Exp e1,e2,e;
      list<tuple<Integer, Integer, BackendDAE.Equation>> eqns;
    case ({}) then true;
    case (((_,_,BackendDAE.EQUATION(exp = e1,scalar = e2)) :: eqns)) /* TODO: Algorithms and ArrayEquations */
      equation
        true = Expression.isConst(e1);
        true = Expression.isConst(e2);
      then
        jacobianConstant(eqns);
    case (((_,_,BackendDAE.RESIDUAL_EQUATION(exp = e)) :: eqns))
      equation
        true = Expression.isConst(e);
      then
        jacobianConstant(eqns);
    case (((_,_,BackendDAE.SOLVED_EQUATION(exp = e)) :: eqns))
      equation
        true = Expression.isConst(e);
      then
        jacobianConstant(eqns);
    else then false;
  end matchcontinue;
end jacobianConstant;

protected function jacobianNonlinear "function: jacobianNonlinear
  author: PA
  Check if jacobian indicates a nonlinear system.
  TODO: Algorithms and Array equations"
  input BackendDAE.Variables vars;
  input list<tuple<Integer, Integer, BackendDAE.Equation>> inTplIntegerIntegerEquationLst;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (vars,inTplIntegerIntegerEquationLst)
    local
      DAE.Exp e1,e2,e;
      list<tuple<Integer, Integer, BackendDAE.Equation>> xs;

    case (_,((_,_,BackendDAE.EQUATION(exp = e1,scalar = e2)) :: xs))
      equation
        false = jacobianNonlinearExp(vars, e1);
        false = jacobianNonlinearExp(vars, e2);
      then
        jacobianNonlinear(vars, xs);
    case (_,((_,_,BackendDAE.RESIDUAL_EQUATION(exp = e)) :: xs))
      equation
        false = jacobianNonlinearExp(vars, e);
      then
        jacobianNonlinear(vars, xs);
    case (_,{}) then false;
    else then true;
  end matchcontinue;
end jacobianNonlinear;

protected function jacobianNonlinearExp "function: jacobianNonlinearExp
  author: PA
  Checks wheter the jacobian indicates a nonlinear system.
  This is true if the jacobian contains any of the variables
  that is solved for."
  input BackendDAE.Variables vars;
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  ((_,(_,outBoolean))) := Expression.traverseExpTopDown(inExp,traverserjacobianNonlinearExp,(vars,false));
end jacobianNonlinearExp;

protected function traverserjacobianNonlinearExp "function traverserjacobianNonlinearExp
  author: Frenkel TUD 2012-08"
  input tuple<DAE.Exp,tuple<BackendDAE.Variables,Boolean>> tpl;
  output tuple<DAE.Exp,Boolean, tuple<BackendDAE.Variables,Boolean>> outTpl;
algorithm
  outTpl := matchcontinue(tpl)
    local
      BackendDAE.Variables vars;
      DAE.Exp e;
      DAE.ComponentRef cr;
      Boolean b;
    case((e as DAE.CREF(componentRef=cr),(vars,_)))
      equation
        (_::_,_) = BackendVariable.getVar(cr, vars);
      then 
        ((e,false,(vars,true)));
    case((e as DAE.CALL(path=Absyn.IDENT(name = "der"),expLst={DAE.CREF(componentRef=cr)}),(vars,_)))
      equation
        (_,_) = BackendVariable.getVar(cr, vars);
      then 
        ((e,false,(vars,true)));
    case((e as DAE.CALL(path=Absyn.IDENT(name = "pre")),(vars,b)))
      then
        ((e,false,(vars,b)));
    case ((e,(vars,b))) then ((e,not b,(vars,b)));
  end matchcontinue;
end traverserjacobianNonlinearExp;

protected function containAnyVar "function: containAnyVar
  author: PA
  Returns true if any of the variables given
  as ComponentRef list is among the BackendDAE.Variables."
  input list<DAE.ComponentRef> inExpComponentRefLst;
  input BackendDAE.Variables inVariables;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExpComponentRefLst,inVariables)
    local
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crefs;
      BackendDAE.Variables vars;
    case ({},_) then false;
    case ((cr :: crefs),vars)
      equation
        (_,_) = BackendVariable.getVar(cr, vars);
      then
        true;
    case ((_ :: crefs),vars)
      then
       containAnyVar(crefs, vars);
  end matchcontinue;
end containAnyVar;

public function getEqnsysRhsExp "function: getEqnsysRhsExp
  author: PA

  Retrieve the right hand side expression of an equation
  in an equation system, given a set of variables.
  Uses f(x) = g(x) -> 0 = f(x)-g(x) -> x=0 -> rhs= f(0)-g(0).
  Does not work for nonlinear Equations. 

  inputs:  (DAE.Exp, BackendDAE.Variables /* variables of the eqn sys. */)
  outputs:  DAE.Exp =
"
  input DAE.Exp inExp;
  input BackendDAE.Variables inVariables;
  input Option<DAE.FunctionTree> funcs;
  output DAE.Exp outExp;
protected
  BackendVarTransform.VariableReplacements repl;
algorithm
  repl := makeZeroReplacements(inVariables);
  ((outExp,(_,_,_,true))) := Expression.traverseExpTopDown(inExp, getEqnsysRhsExp1, (repl,inVariables,funcs,true));
  (outExp,_) := ExpressionSimplify.simplify(outExp);
end getEqnsysRhsExp;

protected function getEqnsysRhsExp1
  input tuple<DAE.Exp, tuple<BackendVarTransform.VariableReplacements,BackendDAE.Variables,Option<DAE.FunctionTree>,Boolean>> inTplExpTypeA;
  output tuple<DAE.Exp, Boolean, tuple<BackendVarTransform.VariableReplacements,BackendDAE.Variables,Option<DAE.FunctionTree>,Boolean>> outTplExpBoolTypeA;
algorithm
  outTplExpBoolTypeA := match(inTplExpTypeA)
    local
      DAE.Exp cond,t,f,e,e1;
      BackendVarTransform.VariableReplacements repl;
      BackendDAE.Variables vars;
      Boolean b,b1;
      Absyn.Path path;
      list<DAE.Exp> expLst;
      Option<DAE.FunctionTree> funcs;
    case ((e as DAE.CREF(ty=_),(repl,vars,funcs,b)))
      equation
        (e1,b1) = BackendVarTransform.replaceExp(e, repl, NONE());
        e1 = Util.if_(b1,e1,e);
      then
        ((e1,false,(repl,vars,funcs,b)));  
    case ((DAE.IFEXP(cond,t,f),(repl,vars,funcs,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpTopDown(cond, getEqnsysRhsExp2, (vars,b));
        ((t,(_,_,_,b))) = Expression.traverseExpTopDown(t, getEqnsysRhsExp1, (repl,vars,funcs,b));
        ((f,(_,_,_,b))) = Expression.traverseExpTopDown(f, getEqnsysRhsExp1, (repl,vars,funcs,b));
      then
        ((DAE.IFEXP(cond,t,f),false,(repl,vars,funcs,b)));  
    case ((e as DAE.CALL(path = path as Absyn.IDENT(name = "der")),(repl,vars,funcs,b)))
      then
        ((e,true,(repl,vars,funcs,b)));         
    case ((e as DAE.CALL(path = Absyn.IDENT(name = "pre")),(repl,vars,funcs,b)))
      then
        ((e,false,(repl,vars,funcs,b)));         
    case ((e as DAE.CALL(expLst=expLst),(repl,vars,funcs,b)))
      equation
        // check if vars not in condition
        ((_,(_,b))) = Expression.traverseExpListTopDown(expLst, getEqnsysRhsExp2, (vars,b));
        (e,b) = getEqnsysRhsExp3(b,e,(repl,vars,funcs,true));
      then
        ((e,false,(repl,vars,funcs,b)));         
    case ((e,(repl,vars,funcs,b))) then ((e,b,(repl,vars,funcs,b)));
  end match;
end getEqnsysRhsExp1;

protected function getEqnsysRhsExp3
  input Boolean b;
  input DAE.Exp inExp;
  input tuple<BackendVarTransform.VariableReplacements,BackendDAE.Variables,Option<DAE.FunctionTree>,Boolean> iTpl;
  output DAE.Exp oExp;
  output Boolean notfound;
algorithm
  (oExp,notfound) := matchcontinue(b,inExp,iTpl)
  local
    Option<DAE.FunctionTree> funcs;
    DAE.Exp e;
  case (false,_,(_,_,funcs,_))
    equation
      // try to inline
      (e,_,true) = Inline.forceInlineExp(inExp,(funcs,{DAE.NORM_INLINE(),DAE.NO_INLINE()}),DAE.emptyElementSource);
      e = Expression.addNoEventToRelations(e);
      ((e,(_,_,_,notfound))) = Expression.traverseExpTopDown(e, getEqnsysRhsExp1, iTpl);
    then
      (e,notfound);
  case (_,_,_) then (inExp,b);
  end matchcontinue;
end getEqnsysRhsExp3;

protected function getEqnsysRhsExp2
  input tuple<DAE.Exp, tuple<BackendDAE.Variables,Boolean>> inTplExpTypeA;
  output tuple<DAE.Exp, Boolean, tuple<BackendDAE.Variables,Boolean>> outTplExpBoolTypeA;
algorithm
  outTplExpBoolTypeA := matchcontinue(inTplExpTypeA)
    local
      DAE.Exp e;
      BackendDAE.Variables vars;
      DAE.ComponentRef cr;
      Boolean b;
    // special case for time, it is never part of the equation system  
    case ((e as DAE.CREF(componentRef = DAE.CREF_IDENT(ident="time")),(vars,b)))
      then ((e, false, (vars,b)));
        
    // case for functionpointers    
    case ((e as DAE.CREF(ty=DAE.T_FUNCTION_REFERENCE_FUNC(builtin=_)),(vars,b)))
      then
        ((e, false, (vars,b)));

    case ((e as DAE.CALL(path = Absyn.IDENT(name = "pre")),(vars,b)))
      then
        ((e,false,(vars,b)));         
    // found ?
    case ((e as DAE.CREF(componentRef = cr),(vars,_)))
      equation
         (_::_,_) = BackendVariable.getVar(cr, vars);
      then
        ((e, false,(vars,false)));

    case ((e,(vars,b))) then ((e,b,(vars,b)));
  end matchcontinue;
end getEqnsysRhsExp2;

protected function makeZeroReplacements "
  Help function to ifBranchesFreeFromVar, creates replacement rules
  v -> 0, for all variables"
  input BackendDAE.Variables vars;
  output BackendVarTransform.VariableReplacements repl;
algorithm
  repl := BackendVariable.traverseBackendDAEVars(vars,makeZeroReplacement,BackendVarTransform.emptyReplacements());
end makeZeroReplacements;

protected function makeZeroReplacement "helper function to makeZeroReplacements.
Creates replacement Var-> 0"
  input tuple<Var, BackendVarTransform.VariableReplacements> inTpl;
  output tuple<Var, BackendVarTransform.VariableReplacements> outTpl;
algorithm
  outTpl:=
  matchcontinue (inTpl)
    local    
     Var var;
     DAE.ComponentRef cr;
     BackendVarTransform.VariableReplacements repl,repl1;
    case ((var,repl))
      equation
        cr =  BackendVariable.varCref(var);
        repl1 = BackendVarTransform.addReplacement(repl,cr,Expression.makeConstZero(ComponentReference.crefLastType(cr)),NONE());
      then
        ((var,repl1));
    else then inTpl;
  end matchcontinue;
end makeZeroReplacement;

/*************************************************
 * traverseBackendDAE and stuff
 ************************************************/
public function traverseBackendDAEExps "function: traverseBackendDAEExps
  author: Frenkel TUD

  This function goes through the BackendDAE structure and finds all the
  expressions and performs the function on them in a list 
  an extra argument passed through the function.
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.BackendDAE inBackendDAE;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA:=
  matchcontinue (inBackendDAE,func,inTypeA)
    local
      BackendDAE.Variables vars2;
      EquationArray reqns,ieqns;
      list<WhenClause> whenClauseLst;
      Type_a ext_arg_1,ext_arg_2,ext_arg_4,ext_arg_5,ext_arg_6;
      list<BackendDAE.EqSystem> systs;
    case (BackendDAE.DAE(eqs=systs,shared=BackendDAE.SHARED(knownVars = vars2,initialEqs = ieqns,removedEqs = reqns, eventInfo = BackendDAE.EVENT_INFO(whenClauseLst=whenClauseLst))),_,_)
      equation
        ext_arg_1 = List.fold1(systs,traverseBackendDAEExpsEqSystem,func,inTypeA);
        ext_arg_2 = traverseBackendDAEExpsVars(vars2,func,ext_arg_1);
        ext_arg_4 = traverseBackendDAEExpsEqns(reqns,func,ext_arg_2);
        ext_arg_5 = traverseBackendDAEExpsEqns(ieqns,func,ext_arg_4);
        (_,ext_arg_6) = BackendDAETransform.traverseBackendDAEExpsWhenClauseLst(whenClauseLst,func,ext_arg_5);
      then
        ext_arg_6;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.traverseBackendDAEExps failed"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExps;

public function traverseBackendDAEExpsNoCopyWithUpdate "
  This function goes through the BackendDAE structure and finds all the
  expressions and performs the function on them in a list 
  an extra argument passed through the function.
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.BackendDAE inBackendDAE;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA:=
  matchcontinue (inBackendDAE,func,inTypeA)
    local
      BackendDAE.Variables vars2;
      EquationArray reqns,ieqns;
      Type_a ext_arg_1,ext_arg_2,ext_arg_4,ext_arg_5,ext_arg_6;
      list<BackendDAE.EqSystem> systs;
      list<BackendDAE.WhenClause> wc;
    case (BackendDAE.DAE(eqs=systs,shared=BackendDAE.SHARED(knownVars = vars2,initialEqs = ieqns,removedEqs = reqns,eventInfo=BackendDAE.EVENT_INFO(whenClauseLst=wc))),_,_)
      equation
        ext_arg_1 = List.fold1(systs,traverseBackendDAEExpsEqSystemWithUpdate,func,inTypeA);
        ext_arg_2 = traverseBackendDAEExpsVarsWithUpdate(vars2,func,ext_arg_1);
        ext_arg_4 = traverseBackendDAEExpsEqnsWithUpdate(reqns,func,ext_arg_2);
        ext_arg_5 = traverseBackendDAEExpsEqnsWithUpdate(ieqns,func,ext_arg_4);
        (_,ext_arg_6) = BackendDAETransform.traverseBackendDAEExpsWhenClauseLst(wc,func,ext_arg_5);
      then
        ext_arg_6;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.traverseBackendDAEExpsNoCopyWithUpdate failed"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsNoCopyWithUpdate;

public function traverseBackendDAEExpsEqSystem "function: traverseBackendDAEExps
  author: Frenkel TUD

  This function goes through the BackendDAE structure and finds all the
  expressions and performs the function on them in a list 
  an extra argument passed through the function.
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.EqSystem syst;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
protected
  BackendDAE.Variables vars;
  EquationArray eqns;
algorithm
  BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns) := syst;
  outTypeA := traverseBackendDAEExpsVars(vars,func,inTypeA);
  outTypeA := traverseBackendDAEExpsEqns(eqns,func,outTypeA);
end traverseBackendDAEExpsEqSystem;

public function traverseBackendDAEExpsEqSystemWithUpdate "function: traverseBackendDAEExps
  author: Frenkel TUD

  This function goes through the BackendDAE structure and finds all the
  expressions and performs the function on them in a list 
  an extra argument passed through the function.
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.EqSystem syst;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
protected
  BackendDAE.Variables vars;
  EquationArray eqns;
algorithm
  BackendDAE.EQSYSTEM(orderedVars = vars,orderedEqs = eqns) := syst;
  outTypeA := traverseBackendDAEExpsVarsWithUpdate(vars,func,inTypeA);
  outTypeA := traverseBackendDAEExpsEqnsWithUpdate(eqns,func,outTypeA);
end traverseBackendDAEExpsEqSystemWithUpdate;

public function traverseBackendDAEExpsVars "function: traverseBackendDAEExpsVars
  author: Frenkel TUD

  Helper for traverseBackendDAEExps
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.Variables inVariables;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA:=
  matchcontinue (inVariables,func,inTypeA)
    local
      array<Option<Var>> varOptArr;
      Type_a ext_arg_1;
    case (BackendDAE.VARIABLES(varArr = BackendDAE.VARIABLE_ARRAY(varOptArr=varOptArr)),_,_)
      equation
        ext_arg_1 = traverseBackendDAEArrayNoCopy(varOptArr,func,traverseBackendDAEExpsVar,1,arrayLength(varOptArr),inTypeA);
      then
        ext_arg_1;
    else
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.traverseBackendDAEExpsVars failed");
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsVars;

public function traverseBackendDAEExpsVarsWithUpdate "function: traverseBackendDAEExpsVars
  author: Frenkel TUD

  Helper for traverseBackendDAEExps
"
  replaceable type Type_a subtypeof Any;
  input BackendDAE.Variables inVariables;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA:=
  matchcontinue (inVariables,func,inTypeA)
    local
      array<Option<Var>> varOptArr;
      Type_a ext_arg_1;
    case (BackendDAE.VARIABLES(varArr = BackendDAE.VARIABLE_ARRAY(varOptArr=varOptArr)),_,_)
      equation
        (_,ext_arg_1) = traverseBackendDAEArrayNoCopyWithUpdate(varOptArr,func,traverseBackendDAEExpsVarWithUpdate,1,arrayLength(varOptArr),inTypeA);
      then
        ext_arg_1;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.traverseBackendDAEExpsVarsWithUpdate failed"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsVarsWithUpdate;

public function traverseBackendDAEArrayNoCopy "
 help function to traverseBackendDAEExps
 author: Frenkel TUD"
  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;
  replaceable type Type_c subtypeof Any;
  input array<Type_a> inArray;
  input FuncExpType func;
  input FuncArrayType arrayfunc;
  input Integer pos "iterated 1..len";
  input Integer len "length of array";
  input Type_b inTypeB;
  output Type_b outTypeB;
  partial function FuncExpType
    input tuple<Type_c, Type_b> inTpl;
    output tuple<Type_c, Type_b> outTpl;
  end FuncExpType;
  partial function FuncArrayType
    input Type_a inTypeA;
    input FuncExpType func;
    input Type_b inTypeB;
    output Type_b outTypeB;
    partial function FuncExpType
     input tuple<Type_c, Type_b> inTpl;
     output tuple<Type_c, Type_b> outTpl;
    end FuncExpType;
  end FuncArrayType;
algorithm
  outTypeB := matchcontinue(inArray,func,arrayfunc,pos,len,inTypeB)
    local 
      Type_b ext_arg_1,ext_arg_2;
    case(_,_,_,_,_,_) equation 
      true = pos > len;
    then inTypeB;
    
    case(_,_,_,_,_,_) equation
      ext_arg_1 = arrayfunc(inArray[pos],func,inTypeB);
      ext_arg_2 = traverseBackendDAEArrayNoCopy(inArray,func,arrayfunc,pos+1,len,ext_arg_1);
    then ext_arg_2;
  end matchcontinue;
end traverseBackendDAEArrayNoCopy;

public function traverseBackendDAEArrayNoCopyWithStop "
 help function to traverseBackendDAEArrayNoCopyWithStop
 author: Frenkel TUD
  same like traverseBackendDAEArrayNoCopy but with a additional
  parameter to stop the traveral."
  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;
  replaceable type Type_c subtypeof Any;
  input array<Type_a> inArray;
  input FuncExpTypeWithStop func;
  input FuncArrayTypeWithStop arrayfunc;
  input Integer pos "iterated 1..len";
  input Integer len "length of array";
  input Type_b inTypeB;
  output Type_b outTypeB;
  partial function FuncExpTypeWithStop
    input tuple<Type_c, Type_b> inTpl;
    output tuple<Type_c, Boolean, Type_b> outTpl;
  end FuncExpTypeWithStop;
  partial function FuncArrayTypeWithStop
    input Type_a inTypeA;
    input FuncExpTypeWithStop func;
    input Type_b inTypeB;
    output Boolean outBoolean;
    output Type_b outTypeB;
    partial function FuncExpTypeWithStop
     input tuple<Type_c, Type_b> inTpl;
      output tuple<Type_c, Boolean, Type_b> outTpl;
    end FuncExpTypeWithStop;
  end FuncArrayTypeWithStop;
algorithm
  outTypeB := matchcontinue(inArray,func,arrayfunc,pos,len,inTypeB)
    local 
      Type_b ext_arg_1,ext_arg_2;
      Boolean b;
    case(_,_,_,_,_,_) equation 
      true = pos > len;
    then inTypeB;    
    case(_,_,_,_,_,_) equation
      (b,ext_arg_1) = arrayfunc(inArray[pos],func,inTypeB);
      ext_arg_2 = Debug.bcallret6(b,traverseBackendDAEArrayNoCopyWithStop,inArray,func,arrayfunc,pos+1,len,ext_arg_1,ext_arg_1);
    then ext_arg_2;
  end matchcontinue;
end traverseBackendDAEArrayNoCopyWithStop;

public function traverseBackendDAEArrayNoCopyWithUpdate "
 help function to traverseBackendDAEExps
 author: Frenkel TUD"
  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;
  replaceable type Type_c subtypeof Any;
  input array<Type_a> inArray;
  input FuncExpType func;
  input FuncArrayTypeWithUpdate arrayfunc;
  input Integer pos "iterated 1..len";
  input Integer len "length of array";
  input Type_b inTypeB;
  output array<Type_a> outArray;
  output Type_b outTypeB;
  partial function FuncExpType
    input tuple<Type_c, Type_b> inTpl;
    output tuple<Type_c, Type_b> outTpl;
  end FuncExpType;
  partial function FuncArrayTypeWithUpdate
    input Type_a inTypeA;
    input FuncExpType func;
    input Type_b inTypeB;
    output Type_a outTypeA;
    output Type_b outTypeB;
    partial function FuncExpTypeWithUpdate
     input tuple<Type_c, Type_b> inTpl;
     output tuple<Type_c, Type_b> outTpl;
    end FuncExpTypeWithUpdate;
  end FuncArrayTypeWithUpdate;
algorithm
  (outArray,outTypeB) := matchcontinue(inArray,func,arrayfunc,pos,len,inTypeB)
    local 
      array<Type_a> newarray;
      Type_a a,new_a;
      Type_b ext_arg_1,ext_arg_2;
    case(_,_,_,_,_,_) equation 
      true = pos > len;
    then (inArray,inTypeB);
    
    case(_,_,_,_,_,_) equation
      a = inArray[pos];
      (new_a,ext_arg_1) = arrayfunc(a,func,inTypeB);
      newarray = arrayUpdateCond(referenceEq(a,new_a),inArray,pos,new_a);      
      (newarray,ext_arg_2) = traverseBackendDAEArrayNoCopyWithUpdate(newarray,func,arrayfunc,pos+1,len,ext_arg_1);
    then (newarray,ext_arg_2);
  end matchcontinue;
end traverseBackendDAEArrayNoCopyWithUpdate;

protected function arrayUpdateCond
  input Boolean b;
  input array<Type_a> inArray;
  input Integer pos;
  input Type_a a;
  output array<Type_a> outArray;
  replaceable type Type_a subtypeof Any;
algorithm
  outArray := match(b,inArray,pos,a)
    case(true,_,_,_) // equation print("equal\n"); 
      then inArray; 
    case(false,_,_,_) // equation print("not equal\n"); 
      then arrayUpdate(inArray,pos,a);
  end match;
end arrayUpdateCond;  

protected function traverseBackendDAEExpsVar "function: traverseBackendDAEExpsVar
  author: Frenkel TUD
  Helper traverseBackendDAEExpsVar. Get all exps from a  Var.
  DAE.T_UNKNOWN_DEFAULT is used as type for componentref. Not important here.
  We only use the exp list for finding function calls"
  replaceable type Type_a subtypeof Any;
  input Option<Var> inVar;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (_,outTypeA):=traverseBackendDAEExpsVarWithUpdate(inVar,func,inTypeA);
end traverseBackendDAEExpsVar;

protected function traverseBackendDAEExpsVarWithUpdate "function: traverseBackendDAEExpsVar
  author: Frenkel TUD
  Helper traverseBackendDAEExpsVar. Get all exps from a  Var.
  DAE.T_UNKNOWN_DEFAULT is used as type for componentref. Not important here.
  We only use the exp list for finding function calls"
  replaceable type Type_a subtypeof Any;
  input Option<Var> inVar;
  input FuncExpType func;
  input Type_a inTypeA;
  output Option<Var> ovar;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (ovar,outTypeA) :=
  matchcontinue (inVar,func,inTypeA)
    local
      DAE.Exp e1;
      DAE.ComponentRef cref;
      list<DAE.Subscript> instdims;
      Option<DAE.VariableAttributes> attr;
      Type_a ext_arg_1,ext_arg_2;
      VarKind varKind;
      DAE.VarDirection varDirection;
      DAE.VarParallelism varParallelism;
      BackendDAE.Type varType;
      Option<Values.Value> bindValue;
      DAE.ElementSource source;
      Option<SCode.Comment> comment;
      DAE.ConnectorType ct;
    
    case (NONE(),_,_) then (NONE(),inTypeA);
    
    case (SOME(BackendDAE.VAR(cref,varKind,varDirection,varParallelism,varType,SOME(e1),bindValue,instdims,source,attr,comment,ct)),_,_)
      equation
        ((e1,ext_arg_1)) = func((e1,inTypeA));
        (instdims,ext_arg_2) = List.map1Fold(instdims,traverseBackendDAEExpsSubscriptWithUpdate,func,ext_arg_1);        
        (attr,ext_arg_2) = traverseBackendDAEVarAttr(attr,func,ext_arg_2);        
      then
        (SOME(BackendDAE.VAR(cref,varKind,varDirection,varParallelism,varType,SOME(e1),bindValue,instdims,source,attr,comment,ct)),ext_arg_2);
    
    case (SOME(BackendDAE.VAR(cref,varKind,varDirection,varParallelism,varType,NONE(),bindValue,instdims,source,attr,comment,ct)),_,_)
      equation
        (instdims,ext_arg_2) = List.map1Fold(instdims,traverseBackendDAEExpsSubscriptWithUpdate,func,inTypeA);        
        (attr,ext_arg_2) = traverseBackendDAEVarAttr(attr,func,ext_arg_2);
      then
        (SOME(BackendDAE.VAR(cref,varKind,varDirection,varParallelism,varType,NONE(),bindValue,instdims,source,attr,comment,ct)),ext_arg_2);
    
    else
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.traverseBackendDAEExpsVar failed");
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsVarWithUpdate;

public function traverseBackendDAEVarAttr 
"help function to traverseBackendDAEExpsVarWithUpdate
author: Peter Aronsson (paronsson@wolfram.com)
"
  input Option<DAE.VariableAttributes> attr;
  input funcType func;
  input ExtraArgType extraArg;
  replaceable type ExtraArgType subtypeof Any; 
  partial function funcType
    input tuple<DAE.Exp,ExtraArgType> inTpl;
    output tuple<DAE.Exp,ExtraArgType> outTpl;
  end funcType;
  output Option<DAE.VariableAttributes> outAttr;
  output ExtraArgType outExtraArg;
algorithm
 (outAttr,outExtraArg) := match(attr,func,extraArg)
   local
     Option<DAE.Exp> q,u,du,min,max,i,f,n,eqbound,startOrigin;
     Option<DAE.StateSelect> ss;
     Option<DAE.Uncertainty> unc;
     Option<DAE.Distribution> dist;
     Option<Boolean> p,fin;
   case(NONE(),_,_) then (NONE(),extraArg);
   case(SOME(DAE.VAR_ATTR_REAL(q,u,du,(min,max),i,f,n,ss,unc,dist,eqbound,p,fin,startOrigin)),_,_) equation
     ((q,outExtraArg)) = Expression.traverseExpOpt(q,func,extraArg);
     ((u,outExtraArg)) = Expression.traverseExpOpt(u,func,outExtraArg);
     ((du,outExtraArg)) = Expression.traverseExpOpt(du,func,outExtraArg);
     ((min,outExtraArg)) = Expression.traverseExpOpt(min,func,outExtraArg);
     ((max,outExtraArg)) = Expression.traverseExpOpt(max,func,outExtraArg);
     ((i,outExtraArg)) = Expression.traverseExpOpt(i,func,outExtraArg);
     ((f,outExtraArg)) = Expression.traverseExpOpt(f,func,outExtraArg);
     ((n,outExtraArg)) = Expression.traverseExpOpt(n,func,outExtraArg);
     ((eqbound,outExtraArg)) = Expression.traverseExpOpt(eqbound,func,outExtraArg);
     (dist,outExtraArg) = traverseBackendDAEAttrDistribution(dist,func,outExtraArg);
   then (SOME(DAE.VAR_ATTR_REAL(q,u,du,(min,max),i,f,n,ss,unc,dist,eqbound,p,fin,startOrigin)),outExtraArg);
          
   case(SOME(DAE.VAR_ATTR_INT(q,(min,max),i,f,unc,dist,eqbound,p,fin,startOrigin)),_,_) equation
     ((q,outExtraArg)) = Expression.traverseExpOpt(q,func,extraArg);
     ((min,outExtraArg)) = Expression.traverseExpOpt(min,func,outExtraArg);
     ((max,outExtraArg)) = Expression.traverseExpOpt(max,func,outExtraArg);
     ((i,outExtraArg)) = Expression.traverseExpOpt(i,func,outExtraArg);
     ((f,outExtraArg)) = Expression.traverseExpOpt(f,func,outExtraArg);
     ((eqbound,outExtraArg)) = Expression.traverseExpOpt(eqbound,func,outExtraArg);
      (dist,outExtraArg) = traverseBackendDAEAttrDistribution(dist,func,outExtraArg);
   then (SOME(DAE.VAR_ATTR_INT(q,(min,max),i,f,unc,dist,eqbound,p,fin,startOrigin)),outExtraArg);
          
   case(SOME(DAE.VAR_ATTR_BOOL(q,i,f,eqbound,p,fin,startOrigin)),_,_) equation
     ((q,outExtraArg)) = Expression.traverseExpOpt(q,func,extraArg);
     ((i,outExtraArg)) = Expression.traverseExpOpt(i,func,outExtraArg);
     ((f,outExtraArg)) = Expression.traverseExpOpt(f,func,outExtraArg);
     ((eqbound,outExtraArg)) = Expression.traverseExpOpt(eqbound,func,outExtraArg);
   then (SOME(DAE.VAR_ATTR_BOOL(q,i,f,eqbound,p,fin,startOrigin)),outExtraArg);
     
   case(SOME(DAE.VAR_ATTR_STRING(q,i,eqbound,p,fin,startOrigin)),_,_) equation
     ((q,outExtraArg)) = Expression.traverseExpOpt(q,func,extraArg);
     ((i,outExtraArg)) = Expression.traverseExpOpt(i,func,outExtraArg);
     ((eqbound,outExtraArg)) = Expression.traverseExpOpt(eqbound,func,outExtraArg);
   then (SOME(DAE.VAR_ATTR_STRING(q,i,eqbound,p,fin,startOrigin)),outExtraArg);
     
   case(SOME(DAE.VAR_ATTR_ENUMERATION(q,(min,max),i,f,eqbound,p,fin,startOrigin)),_,_) equation
      ((q,outExtraArg)) = Expression.traverseExpOpt(q,func,extraArg);
     ((min,outExtraArg)) = Expression.traverseExpOpt(min,func,outExtraArg);
     ((max,outExtraArg)) = Expression.traverseExpOpt(max,func,outExtraArg);
     ((i,outExtraArg)) = Expression.traverseExpOpt(i,func,outExtraArg);
     ((f,outExtraArg)) = Expression.traverseExpOpt(f,func,outExtraArg);
     ((eqbound,outExtraArg)) = Expression.traverseExpOpt(eqbound,func,outExtraArg);
    then (SOME(DAE.VAR_ATTR_ENUMERATION(q,(min,max),i,f,eqbound,p,fin,startOrigin)),outExtraArg);
           
 end match;
end traverseBackendDAEVarAttr;

protected function traverseBackendDAEAttrDistribution 
"help function to traverseBackendDAEVarAttr
author: Peter Aronsson (paronsson@wolfram.com)
"
  input Option<DAE.Distribution> distOpt;
  input funcType func;
  input ExtraArgType extraArg;
  replaceable type ExtraArgType subtypeof Any; 
  partial function funcType
    input tuple<DAE.Exp,ExtraArgType> inTpl;
    output tuple<DAE.Exp,ExtraArgType> outTpl;
  end funcType;
  output Option<DAE.Distribution> outDistOpt;
  output ExtraArgType outExtraArg;
algorithm
 (outDistOpt,outExtraArg) := match(distOpt,func,extraArg)
 local
   DAE.Exp name,arr,sarr;
   
   case(NONE(),_,outExtraArg) then (NONE(),outExtraArg);
   
   case(SOME(DAE.DISTRIBUTION(name,arr,sarr)),_,_) equation
     ((arr,_)) = extendArrExp((arr,(NONE(),false)));
     ((sarr,_)) = extendArrExp((sarr,(NONE(),false)));
     ((name,outExtraArg)) = Expression.traverseExp(name,func,extraArg);
     ((arr,outExtraArg)) = Expression.traverseExp(arr,func,outExtraArg);
     ((sarr,outExtraArg)) = Expression.traverseExp(sarr,func,outExtraArg);
    then (SOME(DAE.DISTRIBUTION(name,arr,sarr)),outExtraArg);
 end match;
end traverseBackendDAEAttrDistribution;

protected function traverseBackendDAEExpsSubscript "function: traverseBackendDAEExpsSubscript
  author: Frenkel TUD
  helper for traverseBackendDAEExpsSubscript"
  replaceable type Type_a subtypeof Any;
  input DAE.Subscript inSubscript;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA:=
  match (inSubscript,func,inTypeA)
    local
      DAE.Exp e;
      Type_a ext_arg_1;
    case (DAE.WHOLEDIM(),_,_) then inTypeA;
    case (DAE.SLICE(exp = e),_,_)
      equation
        ((_,ext_arg_1)) = func((e,inTypeA));
      then ext_arg_1;
    case (DAE.INDEX(exp = e),_,_)
      equation
        ((_,ext_arg_1)) = func((e,inTypeA));
      then ext_arg_1;
  end match;
end traverseBackendDAEExpsSubscript;

protected function traverseBackendDAEExpsSubscriptWithUpdate "function: traverseBackendDAEExpsSubscript
  author: Frenkel TUD
  helper for traverseBackendDAEExpsSubscript"
  replaceable type Type_a subtypeof Any;
  input DAE.Subscript inSubscript;
  input FuncExpType func;
  input Type_a inTypeA;
  output DAE.Subscript outSubscript;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outSubscript,outTypeA) :=
  match (inSubscript,func,inTypeA)
    local
      DAE.Exp e;
      Type_a ext_arg_1;
    case (DAE.WHOLEDIM(),_,_) then (DAE.WHOLEDIM(),inTypeA);
    case (DAE.SLICE(exp = e),_,_)
      equation
        ((e,ext_arg_1)) = func((e,inTypeA));
      then (DAE.SLICE(e),ext_arg_1);
    case (DAE.INDEX(exp = e),_,_)
      equation
        ((e,ext_arg_1)) = func((e,inTypeA));
      then (DAE.INDEX(e),ext_arg_1);
  end match;
end traverseBackendDAEExpsSubscriptWithUpdate;

public function traverseBackendDAEExpsEqns "function: traverseBackendDAEExpsEqns
  author: Frenkel TUD

  Helper for traverseBackendDAEExpsEqns
"
  replaceable type Type_a subtypeof Any;
  input EquationArray inEquationArray;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA :=
  matchcontinue (inEquationArray,func,inTypeA)
    local
      array<Option<BackendDAE.Equation>> equOptArr;
    case ((BackendDAE.EQUATION_ARRAY(equOptArr = equOptArr)),_,_)
      then traverseBackendDAEArrayNoCopy(equOptArr,func,traverseBackendDAEExpsOptEqn,1,arrayLength(equOptArr),inTypeA);
    else
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.traverseBackendDAEExpsEqns failed");
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsEqns;

public function traverseBackendDAEExpsEqnsWithStop "function: traverseBackendDAEExpsEqnsWithStop
  author: Frenkel TUD

  Helper for traverseBackendDAEExpsEqns
"
  replaceable type Type_a subtypeof Any;
  input EquationArray inEquationArray;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Boolean, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA :=
  matchcontinue (inEquationArray,func,inTypeA)
    local
      array<Option<BackendDAE.Equation>> equOptArr;
    case ((BackendDAE.EQUATION_ARRAY(equOptArr = equOptArr)),_,_)
      then traverseBackendDAEArrayNoCopyWithStop(equOptArr,func,traverseBackendDAEExpsOptEqnWithStop,1,arrayLength(equOptArr),inTypeA);
    else
      equation
        Debug.fprintln(Flags.FAILTRACE, "- BackendDAE.traverseBackendDAEExpsEqnsWithStop failed");
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsEqnsWithStop;

public function traverseBackendDAEExpsEqnsWithUpdate "function: traverseBackendDAEExpsEqns
  author: Frenkel TUD

  Helper for traverseBackendDAEExpsEqns
"
  replaceable type Type_a subtypeof Any;
  input EquationArray inEquationArray;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA :=
  matchcontinue (inEquationArray,func,inTypeA)
    local
      array<Option<BackendDAE.Equation>> equOptArr;
    case ((BackendDAE.EQUATION_ARRAY(equOptArr = equOptArr)),_,_)
      equation
        (_,outTypeA) = traverseBackendDAEArrayNoCopyWithUpdate(equOptArr,func,traverseBackendDAEExpsOptEqnWithUpdate,1,arrayLength(equOptArr),inTypeA);
      then outTypeA;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"BackendDAEUtil.traverseBackendDAEExpsEqnsWithUpdate failed"});
      then
        fail();
  end matchcontinue;
end traverseBackendDAEExpsEqnsWithUpdate;

protected function traverseBackendDAEExpsOptEqn "function: traverseBackendDAEExpsOptEqn
  author: Frenkel TUD 2010-11
  Helper for traverseBackendDAEExpsEqn."
  replaceable type Type_a subtypeof Any;
  input Option<BackendDAE.Equation> inEquation;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (_,outTypeA) := traverseBackendDAEExpsOptEqnWithUpdate(inEquation,func,inTypeA);
end traverseBackendDAEExpsOptEqn;

protected function traverseBackendDAEExpsOptEqnWithStop "function: traverseBackendDAEExpsOptEqnWithStop
  author: Frenkel TUD 2010-11
  Helper for traverseBackendDAEExpsOptEqnWithStop."
  replaceable type Type_a subtypeof Any;
  input Option<BackendDAE.Equation> inEquation;
  input FuncExpType func;
  input Type_a inTypeA;
  output Boolean outBoolean;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Boolean, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outBoolean,outTypeA) := match (inEquation,func,inTypeA)
    local
      BackendDAE.Equation eqn;
      Type_a ext_arg_1;
      Boolean b;
    case (NONE(),_,_) then (true,inTypeA);
    case (SOME(eqn),_,_)
      equation
        (b,ext_arg_1) = BackendEquation.traverseBackendDAEExpsEqnWithStop(eqn,func,inTypeA);
      then
        (b,ext_arg_1);
  end match;
end traverseBackendDAEExpsOptEqnWithStop;

protected function traverseBackendDAEExpsOptEqnWithUpdate "function: traverseBackendDAEExpsOptEqn
  author: Frenkel TUD 2010-11
  Helper for traverseBackendDAEExpsEqn."
  replaceable type Type_a subtypeof Any;
  input Option<BackendDAE.Equation> inEquation;
  input FuncExpType func;
  input Type_a inTypeA;
  output Option<BackendDAE.Equation> outEquation;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outEquation,outTypeA) := match (inEquation,func,inTypeA)
    local
      BackendDAE.Equation eqn;
     Type_a ext_arg_1;
    case (NONE(),_,_) then (NONE(),inTypeA);
    case (SOME(eqn),_,_)
      equation
        (eqn,ext_arg_1) = BackendEquation.traverseBackendDAEExpsEqn(eqn,func,inTypeA);
      then
        (SOME(eqn),ext_arg_1);
  end match;
end traverseBackendDAEExpsOptEqnWithUpdate;

public function traverseAlgorithmExps "function: traverseAlgorithmExps

  This function goes through the Algorithm structure and finds all the
  expressions and performs the function on them
"
  replaceable type Type_a subtypeof Any;
  input DAE.Algorithm inAlgorithm;
  input FuncExpType func;
  input Type_a inTypeA;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  outTypeA := match (inAlgorithm,func,inTypeA)
    local
      list<DAE.Statement> stmts;
      Type_a ext_arg_1;
    case (DAE.ALGORITHM_STMTS(statementLst = stmts),_,_)
      equation
        (_,ext_arg_1) = DAEUtil.traverseDAEEquationsStmts(stmts,func,inTypeA);
      then
        ext_arg_1;
  end match;
end traverseAlgorithmExps;

public function traverseAlgorithmExpsWithUpdate "function: traverseAlgorithmExpsWithUpdate 

  This function goes through the Algorithm structure and finds all the
  expressions and performs the function on them
"
  replaceable type Type_a subtypeof Any;
  input DAE.Algorithm inAlgorithm;
  input FuncExpType func;
  input Type_a inTypeA;
  output DAE.Algorithm outAlgorithm;
  output Type_a outTypeA;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> inTpl;
    output tuple<DAE.Exp, Type_a> outTpl;
  end FuncExpType;
algorithm
  (outAlgorithm,outTypeA) := match (inAlgorithm,func,inTypeA)
    local
      list<DAE.Statement> stmts,stmts1;
      Type_a ext_arg_1;
      DAE.Algorithm alg;
    case (DAE.ALGORITHM_STMTS(statementLst = stmts),_,_)
      equation
        (stmts1,ext_arg_1) = DAEUtil.traverseDAEEquationsStmts(stmts,func,inTypeA);
        alg = Util.if_(referenceEq(stmts,stmts1),inAlgorithm,DAE.ALGORITHM_STMTS(stmts1));
      then
        (alg,ext_arg_1);
  end match;
end traverseAlgorithmExpsWithUpdate;

/*
protected function traverseBackendDAEExpsWrapper "function: traverseBackendDAEExpsWrapper
  author: Frenkel TUD

  Helper function to traverse BackendDAE Exps
"
  replaceable type Type_a subtypeof Any;
  input tuple<DAE.Exp, tuple<FuncExpTravers,FuncExpType,Type_a>> inTpl;
  output tuple<DAE.Exp, tuple<FuncExpTravers,FuncExpType,Type_a>> outTpl;
  partial function FuncExpTravers
    input DAE.Exp inExp;
    input FuncExpType func;
    input Type_a inTypeA;
    output tuple<DAE.Exp, Type_a> outTplExpTypeA;    
  end FuncExpTravers;
  partial function FuncExpType
    input tuple<DAE.Exp, Type_a> iTpl;
    output tuple<DAE.Exp, Type_a> oTpl;
  end FuncExpType;
algorithm
  outTpl := match(inTpl)
    local
      DAE.Exp exp,exp1;
      Type_a arg,arg1;
      FuncExpTravers tfunc;
      FuncExpType func;
    case((exp,(tfunc,func,arg)))
      equation
        ((exp1,arg1)) = tfunc(exp,func,arg);
      then
       ((exp1,(tfunc,func,arg1)));
  end match;
end traverseBackendDAEExpsWrapper;
*/
/*************************************************
 * Equation System Pipeline 
 ************************************************/

partial function preoptimiseDAEModule
"function preoptimiseDAEModule 
  This is the interface for pre optimisation modules."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
end preoptimiseDAEModule;

partial function pastoptimiseDAEModule
"function pastoptimiseDAEModule 
  This is the interface for past optimisation modules."
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
end pastoptimiseDAEModule;

partial function StructurallySingularSystemHandlerFunc
  input list<Integer> eqns;
  input Integer actualEqn;
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input array<Integer> inAssignments1;
  input array<Integer> inAssignments2;
  input BackendDAE.StructurallySingularSystemHandlerArg inArg;
  output list<Integer> changedEqns;
  output Integer continueEqn;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output array<Integer> outAssignments1;
  output array<Integer> outAssignments2; 
  output BackendDAE.StructurallySingularSystemHandlerArg outArg;
end StructurallySingularSystemHandlerFunc; 

partial function matchingAlgorithmFunc
"function: matchingAlgorithmFunc
  This is the interface for the matching algorithm"
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input BackendDAE.MatchingOptions inMatchingOptions;
  input StructurallySingularSystemHandlerFunc sssHandler;
  input BackendDAE.StructurallySingularSystemHandlerArg inArg;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output BackendDAE.StructurallySingularSystemHandlerArg outArg;
end matchingAlgorithmFunc;

partial function stateDeselectionFunc
  input BackendDAE.BackendDAE inDAE;
  input list<Option<BackendDAE.StructurallySingularSystemHandlerArg>> inArgs;
  output BackendDAE.BackendDAE outDAE;
end stateDeselectionFunc;

public function getSolvedSystem
" function: getSolvedSystem
  Run the equation system pipeline."
  input BackendDAE.BackendDAE inDAE;
  input Option<list<String>> strPreOptModules;
  input Option<String> strmatchingAlgorithm;
  input Option<String> strdaeHandler;
  input Option<list<String>> strPastOptModules;
  output BackendDAE.BackendDAE outSODE;
protected
  BackendDAE.BackendDAE dae,optdae,sode,sode1,sode2,optsode;
  Option<BackendDAE.IncidenceMatrix> om,omT;
  BackendDAE.IncidenceMatrix m,mT,m_1,mT_1;
  array<Integer> v1,v2,v1_1,v2_1;
  BackendDAE.StrongComponents comps;
  list<tuple<preoptimiseDAEModule,String,Boolean>> preOptModules;
  list<tuple<pastoptimiseDAEModule,String,Boolean>> pastOptModules;
  tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> daeHandler;
  tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  BackendDAE.EqSystem syst;
algorithm
  preOptModules := getPreOptModules(strPreOptModules);
  pastOptModules := getPastOptModules(strPastOptModules);
  matchingAlgorithm := getMatchingAlgorithm(strmatchingAlgorithm);
  daeHandler := getIndexReductionMethod(strdaeHandler);
  
  Debug.fcall(Flags.DUMP_DAE_LOW, print, "dumpdaelow:\n");
  Debug.fcall(Flags.DUMP_DAE_LOW, BackendDump.dump, inDAE);
  System.realtimeTick(BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  // pre optimisation phase
  // Frenkel TUD: why is this neccesarray? it only consumes time!
  _ := traverseBackendDAEExpsNoCopyWithUpdate(inDAE,ExpressionSimplify.simplifyTraverseHelper,0) "simplify all expressions";
  Debug.execStat("preOpt SimplifyAllExp",BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  (optdae,Util.SUCCESS()) := preoptimiseDAE(inDAE,preOptModules);

  // transformation phase (matching and sorting using a index reduction method
  sode := reduceIndexDAE(optdae,NONE(),matchingAlgorithm,daeHandler,true);
  Debug.fcall(Flags.BLT_DUMP, BackendDump.bltdump, ("bltdump",sode));

  // past optimisation phase
  (optsode,Util.SUCCESS()) := pastoptimiseDAE(sode,pastOptModules,matchingAlgorithm,daeHandler);
  sode1 := BackendDAECreate.findZeroCrossings(optsode);
  Debug.execStat("findZeroCrossings",BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  _ := traverseBackendDAEExpsNoCopyWithUpdate(sode1,ExpressionSimplify.simplifyTraverseHelper,0) "simplify all expressions";
  sode2 := calculateValues(sode1);
  Debug.execStat("calculateValue",BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  outSODE := expandAlgorithmsbyInitStmts(sode2);
  Debug.execStat("expandAlgorithmsbyInitStmts",BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  Debug.fcall(Flags.DUMP_INDX_DAE, print, "dumpindxdae:\n");
  Debug.fcall(Flags.DUMP_INDX_DAE, BackendDump.dump, outSODE);
  Debug.fcall(Flags.DUMP_BACKENDDAE_INFO, BackendDump.dumpCompShort, outSODE);
  Debug.fcall(Flags.DUMP_EQNINORDER, BackendDump.dumpEqnsSolved, outSODE);
  checkBackendDAEWithErrorMsg(outSODE);
end getSolvedSystem;

public function preOptimiseBackendDAE
"function preOptimiseBackendDAE 
  Run the optimisation modules"
  input BackendDAE.BackendDAE inDAE;
  input Option<list<String>> strPreOptModules;
  output BackendDAE.BackendDAE outDAE;
protected
  list<tuple<preoptimiseDAEModule,String,Boolean>> preOptModules;
algorithm
  preOptModules := getPreOptModules(strPreOptModules);
  (outDAE,Util.SUCCESS()) := preoptimiseDAE(inDAE,preOptModules);
end preOptimiseBackendDAE;

protected function preoptimiseDAE
"function preoptimiseDAE 
  Run the optimisation modules"
  input BackendDAE.BackendDAE inDAE;
  input list<tuple<preoptimiseDAEModule,String,Boolean>> optModules;
  output BackendDAE.BackendDAE outDAE;
  output Util.Status status;
algorithm
  (outDAE,status) := matchcontinue (inDAE,optModules)
    local 
      BackendDAE.BackendDAE dae,dae1;
      preoptimiseDAEModule optModule;
      list<tuple<preoptimiseDAEModule,String,Boolean>> rest;
      String str,moduleStr;
      Boolean b;
    case (_,{}) 
      equation
        Debug.fcall(Flags.OPT_DAE_DUMP, print, "Pre optimisation done.\n");
      then 
        (inDAE,Util.SUCCESS());
    case (_,(optModule,moduleStr,_)::rest)
      equation
        dae = optModule(inDAE);
        Debug.execStat("preOpt " +& moduleStr,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
        Debug.fcall(Flags.OPT_DAE_DUMP, print, stringAppendList({"\nOptimisation Module ",moduleStr,":\n\n"}));
        Debug.fcall(Flags.OPT_DAE_DUMP, BackendDump.dump, dae);
        (dae1,status) = preoptimiseDAE(dae,rest);
      then (dae1,status);
    case (_,(optModule,moduleStr,b)::rest)
      equation
        Debug.execStat("<failed> preOpt " +& moduleStr,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
        str = stringAppendList({"Optimisation Module ",moduleStr," failed."});
        Debug.bcall2(not b,Error.addMessage, Error.INTERNAL_ERROR, {str});
        (dae,status) = preoptimiseDAE(inDAE,rest);
      then (dae,Util.if_(b,Util.FAILURE(),status));
  end matchcontinue;
end preoptimiseDAE;

public function transformBackendDAE
"function transformBackendDAE 
  Run the matching and index reduction algorithm"
  input BackendDAE.BackendDAE inDAE;
  input Option<MatchingOptions> inMatchingOptions;
  input Option<String> strmatchingAlgorithm;
  input Option<String> strindexReductionMethod;
  output BackendDAE.BackendDAE outDAE;
protected
  tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> indexReductionMethod;
algorithm
  matchingAlgorithm := getMatchingAlgorithm(strmatchingAlgorithm);
  indexReductionMethod := getIndexReductionMethod(strindexReductionMethod);
  outDAE := reduceIndexDAE(inDAE,inMatchingOptions,matchingAlgorithm,indexReductionMethod,true);
end transformBackendDAE;

protected function reduceIndexDAE
"function reduceIndexDAE 
  Run the matching Algorithm.
  In case of an DAE an DAE-Handler is used to reduce
  the index of the dae."
  input BackendDAE.BackendDAE inDAE;
  input Option<BackendDAE.MatchingOptions> inMatchingOptions;
  input tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  input tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> stateDeselection;
  input Boolean dolateinline;
  output BackendDAE.BackendDAE outDAE;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
  list<Option<BackendDAE.StructurallySingularSystemHandlerArg>> args;
  String methodstr;
  stateDeselectionFunc sDfunc;  
algorithm
  BackendDAE.DAE(systs,shared) := inDAE;
  // reduce index
  (systs,shared,args) := mapReduceIndexDAE(systs,shared,inMatchingOptions,matchingAlgorithm,stateDeselection,{},{});
  // do late inline 
  BackendDAE.DAE(systs,shared) := Debug.bcallret1(dolateinline,BackendDAEOptimize.lateInlineFunction,BackendDAE.DAE(systs,shared),BackendDAE.DAE(systs,shared));
  // do state selection
  (_,_,sDfunc,methodstr) := stateDeselection;
  BackendDAE.DAE(systs,shared) := sDfunc(BackendDAE.DAE(systs,shared),args);
  Debug.execStat("transformDAE -> state selection " +& methodstr,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
  // sort assigned equations to blt form
  (systs,shared) := mapSortEqnsDAE(systs,shared,{});
  outDAE := BackendDAE.DAE(systs,shared);
end reduceIndexDAE;

protected function mapReduceIndexDAE
"function transformDAE 
  Run the matching Algorithm.
  In case of an DAE an DAE-Handler is used to reduce
  the index of the dae."
  input list<BackendDAE.EqSystem> isysts;
  input BackendDAE.Shared ishared;
  input Option<BackendDAE.MatchingOptions> inMatchingOptions;
  input tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  input tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> stateDeselection;
  input list<BackendDAE.EqSystem> acc;
  input list<Option<BackendDAE.StructurallySingularSystemHandlerArg>> acc1;
  output list<BackendDAE.EqSystem> osysts;
  output BackendDAE.Shared oshared;
  output list<Option<BackendDAE.StructurallySingularSystemHandlerArg>> oargs;
algorithm
  (osysts,oshared,oargs) := match (isysts,ishared,inMatchingOptions,matchingAlgorithm,stateDeselection,acc,acc1)
    local 
      BackendDAE.EqSystem syst;
      list<BackendDAE.EqSystem> systs;
      BackendDAE.Shared shared;
      Option<BackendDAE.StructurallySingularSystemHandlerArg> arg;
      list<Option<BackendDAE.StructurallySingularSystemHandlerArg>> args;
    case ({},_,_,_,_,_,_) then (listReverse(acc),ishared,listReverse(acc1));
    case (syst::systs,_,_,_,_,_,_)
      equation
        (syst,shared,arg) = reduceIndexDAEWork(syst,ishared,inMatchingOptions,matchingAlgorithm,stateDeselection);
        (systs,shared,args) = mapReduceIndexDAE(systs,shared,inMatchingOptions,matchingAlgorithm,stateDeselection,syst::acc,arg::acc1);
      then (systs,shared,args);
  end match;
end mapReduceIndexDAE;

protected function reduceIndexDAEWork
"function reduceIndexDAEWork 
  Run the matching Algorithm.
  In case of an DAE an DAE-Handler is used to reduce
  the index of the dae."
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  input Option<BackendDAE.MatchingOptions> inMatchingOptions;
  input tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  input tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> stateDeselection;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
  output Option<BackendDAE.StructurallySingularSystemHandlerArg> oArg;
algorithm
  (osyst,oshared,oArg) := matchcontinue (isyst,ishared,inMatchingOptions,matchingAlgorithm,stateDeselection)
    local 
      String str,mAmethodstr,str1;
      BackendDAE.MatchingOptions match_opts;
      matchingAlgorithmFunc matchingAlgorithmfunc;
      BackendDAE.EqSystem syst;
      BackendDAE.Shared shared;     
      BackendDAE.StructurallySingularSystemHandlerArg arg;
      StructurallySingularSystemHandlerFunc sssHandler;
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn;      

    case (BackendDAE.EQSYSTEM(matching=BackendDAE.MATCHING(comps=_)),_,_,_,_)
      then
        (isyst,ishared,NONE());      
    case (BackendDAE.EQSYSTEM(matching=BackendDAE.NO_MATCHING()),_,_,(matchingAlgorithmfunc,mAmethodstr),(sssHandler,str1,_,_))
      equation
        //  print("SystemSize: " +& intString(systemSize(isyst)) +& "\n");
        (syst,_,_,mapEqnIncRow,mapIncRowEqn) = getIncidenceMatrixScalar(isyst,BackendDAE.SOLVABLE());
        match_opts = Util.getOptionOrDefault(inMatchingOptions,(BackendDAE.INDEX_REDUCTION(), BackendDAE.EXACT()));
        arg = IndexReduction.getStructurallySingularSystemHandlerArg(syst,ishared,mapEqnIncRow,mapIncRowEqn);
        (syst,shared,arg) = matchingAlgorithmfunc(syst,ishared, match_opts, sssHandler, arg);
        Debug.execStat("transformDAE -> matchingAlgorithm " +& mAmethodstr +& " index Reduction Method " +& str1,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
      then (syst,shared,SOME(arg));
    case (_,_,_,(_,mAmethodstr),(_,str1,_,_))
      equation
        str = "Transformation Module " +& mAmethodstr +& " index Reduction Method " +& str1 +& " failed!";
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then
        fail();
  end matchcontinue;
end reduceIndexDAEWork;

protected function mapSortEqnsDAE
"function mapSortEqnsDAE 
  Run Tarjans Algorithm."
  input list<BackendDAE.EqSystem> isysts;
  input BackendDAE.Shared ishared;
  input list<BackendDAE.EqSystem> acc;
  output list<BackendDAE.EqSystem> osysts;
  output BackendDAE.Shared oshared;
algorithm
  (osysts,oshared) := match (isysts,ishared,acc)
    local 
      BackendDAE.EqSystem syst;
      list<BackendDAE.EqSystem> systs;
      BackendDAE.Shared shared;
    case ({},_,_) then (listReverse(acc),ishared);
    case ((syst as BackendDAE.EQSYSTEM(matching=BackendDAE.MATCHING(comps=_::_)))::systs,_,_)
      equation
        (systs,shared) = mapSortEqnsDAE(systs,ishared,syst::acc);
      then (systs,shared);
    case (syst::systs,_,_)
      equation
        (syst,shared) = sortEqnsDAEWork(syst,ishared);
        (systs,shared) = mapSortEqnsDAE(systs,shared,syst::acc);
      then (systs,shared);
  end match;
end mapSortEqnsDAE;

protected function sortEqnsDAEWork
"function sortEqnsDAEWork 
  Run Tarjans Algorithm."
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Shared ishared;
  output BackendDAE.EqSystem osyst;
  output BackendDAE.Shared oshared;
algorithm
  (osyst,oshared) := matchcontinue (isyst,ishared)
    local 
      String str;
      BackendDAE.EqSystem syst;   
      array<list<Integer>> mapEqnIncRow;
      array<Integer> mapIncRowEqn; 
    case (_,_)
      equation
        // sorting algorithm
        (syst,_,_,mapEqnIncRow,mapIncRowEqn) = getIncidenceMatrixScalar(isyst,BackendDAE.NORMAL());
        (syst,_) = BackendDAETransform.strongComponentsScalar(syst, ishared,mapEqnIncRow,mapIncRowEqn);        
        Debug.execStat("transformDAE -> sort components",BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
      then (syst,ishared);
    else
      equation
        str = "Transformation Module sort components failed!";
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end matchcontinue;
end sortEqnsDAEWork;

protected function pastoptimiseDAE
"function optimiseDAE 
  Run the optimisation modules"
  input BackendDAE.BackendDAE inDAE;
  input list<tuple<pastoptimiseDAEModule,String,Boolean>> optModules;
  input tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
  input tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> daeHandler;
  output BackendDAE.BackendDAE outDAE;
  output Util.Status status;
algorithm
  (outDAE,status):=
  matchcontinue (inDAE,optModules,matchingAlgorithm,daeHandler)
    local 
      BackendDAE.BackendDAE dae,dae1,dae2;
      pastoptimiseDAEModule optModule;
      list<tuple<pastoptimiseDAEModule,String,Boolean>> rest;
      String str,moduleStr;
      Boolean b;
    case (_,{},_,_) 
      equation
        Debug.fcall(Flags.OPT_DAE_DUMP, print, "Post optimisation done.\n");
      then 
        (inDAE,Util.SUCCESS());
    case (_,(optModule,moduleStr,_)::rest,_,_)
      equation
        dae = optModule(inDAE);
        Debug.execStat("pastOpt " +& moduleStr,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
        Debug.fcall(Flags.OPT_DAE_DUMP, print, stringAppendList({"\nOptimisation Module ",moduleStr,":\n\n"}));
        Debug.fcall(Flags.OPT_DAE_DUMP, BackendDump.dump, dae);
        dae1 = reduceIndexDAE(dae,NONE(),matchingAlgorithm,daeHandler,false);
        (dae2,status) = pastoptimiseDAE(dae1,rest,matchingAlgorithm,daeHandler);
      then
        (dae2,status);
    case (_,(optModule,moduleStr,b)::rest,_,_)
      equation
        Debug.execStat("pastOpt <failed> " +& moduleStr,BackendDAE.RT_CLOCK_EXECSTAT_BACKEND_MODULES);
        str = stringAppendList({"Optimisation Module ",moduleStr," failed."});
        Debug.bcall2(not b,Error.addMessage, Error.INTERNAL_ERROR, {str});
        (dae,status) = pastoptimiseDAE(inDAE,rest,matchingAlgorithm,daeHandler);
      then   
        (dae,Util.if_(b,Util.FAILURE(),status));
  end matchcontinue;
end pastoptimiseDAE;

protected function checkCompsMatching
"Function check if comps are complete, they are not complete 
 if the matching is wrong due to dummyDer"
  input BackendDAE.StrongComponents inComps;
  input Integer inSysSize;
  output Boolean outCheck;
algorithm
  outCheck := countComponents(inComps,0) == inSysSize;
end checkCompsMatching;

protected function countComponents
  input BackendDAE.StrongComponents inComps;
  input Integer inInt;
  output Integer outInt;
algorithm
  outInt :=
  match (inComps,inInt)
    local
      list<Integer> ilst;
      list<String> ls;
      String s;
      Integer i,i1;
      BackendDAE.JacobianType jacType;
      BackendDAE.StrongComponent comp;
      BackendDAE.StrongComponents comps;
      list<tuple<Integer,list<Integer>>> eqnvartpllst;
    case ({},_) then inInt;
    case (BackendDAE.SINGLEEQUATION(var=_)::comps,_)
      equation
        outInt = countComponents(comps,inInt+1);
      then outInt;
    case (BackendDAE.EQUATIONSYSTEM(vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.MIXEDEQUATIONSYSTEM(condSystem=comp,disc_vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        i = countComponents({comp},inInt+i);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.SINGLEARRAY(vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.SINGLEALGORITHM(vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.SINGLECOMPLEXEQUATION(vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.SINGLEWHENEQUATION(vars=ilst)::comps,_)
      equation
        i = listLength(ilst);
        outInt = countComponents(comps,inInt+i);
      then outInt;
    case (BackendDAE.TORNSYSTEM(tearingvars=ilst,otherEqnVarTpl=eqnvartpllst)::comps,_)
      equation
        i = listLength(ilst);
        i1 = listLength(List.flatten(List.map(eqnvartpllst,Util.tuple22)));
        outInt = countComponents(comps,inInt+i+i1);
      then outInt;
  end match;
end countComponents;

public function getSolvedSystemforJacobians
" function: getSolvedSystemforJacobians
  Run the equation system pipeline."
  input BackendDAE.BackendDAE inDAE;
  input Option<list<String>> strPreOptModules;
  input Option<String> strmatchingAlgorithm;
  input Option<String> strdaeHandler;
  input Option<list<String>> strPastOptModules;
  output BackendDAE.BackendDAE outSODE;
protected
  BackendDAE.BackendDAE dae,optdae,sode;
  list<tuple<preoptimiseDAEModule,String,Boolean>> preOptModules;
  list<tuple<pastoptimiseDAEModule,String,Boolean>> pastOptModules;
  tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> daeHandler;
  tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
algorithm

  preOptModules := getPreOptModules(strPreOptModules);
  pastOptModules := getPastOptModules(strPastOptModules);
  matchingAlgorithm := getMatchingAlgorithm(strmatchingAlgorithm);
  daeHandler := getIndexReductionMethod(strdaeHandler);
  
  Debug.fcall(Flags.DUMP_DAE_LOW, print, "dumpdaelow:\n");
  Debug.fcall(Flags.DUMP_DAE_LOW, BackendDump.dump, inDAE);
  // pre optimisation phase
  _ := traverseBackendDAEExps(inDAE,ExpressionSimplify.simplifyTraverseHelper,0) "simplify all expressions";
  (optdae,Util.SUCCESS()) := preoptimiseDAE(inDAE,preOptModules);

  // transformation phase (matching and sorting using a index reduction method
  sode := reduceIndexDAE(optdae,NONE(),matchingAlgorithm,daeHandler,true);
  Debug.fcall(Flags.DUMP_DAE_LOW, BackendDump.bltdump, ("bltdump",sode));

  // past optimisation phase
  (outSODE,Util.SUCCESS()) := pastoptimiseDAE(sode,pastOptModules,matchingAlgorithm,daeHandler);
  _ := traverseBackendDAEExps(outSODE,ExpressionSimplify.simplifyTraverseHelper,0) "simplify all expressions";

  Debug.fcall(Flags.DUMP_INDX_DAE, print, "dumpindxdae:\n");
  Debug.fcall(Flags.DUMP_INDX_DAE, BackendDump.dump, outSODE);
  Debug.fcall(Flags.DUMP_BACKENDDAE_INFO, BackendDump.dumpCompShort, outSODE);
  Debug.fcall(Flags.DUMP_EQNINORDER, BackendDump.dumpEqnsSolved, outSODE);
end getSolvedSystemforJacobians;

/*************************************************
 * index reduction method Selection 
 ************************************************/

public function getIndexReductionMethodString
" function: getIndexReductionMethodString"
  output String strIndexReductionMethod;
algorithm
  strIndexReductionMethod := Config.getIndexReductionMethod();
end getIndexReductionMethodString;

protected function getIndexReductionMethod
" function: getIndexReductionMethod"
  input Option<String> ostrIndexReductionMethod;
  output tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String> IndexReductionMethod;
protected 
  list<tuple<StructurallySingularSystemHandlerFunc,String,stateDeselectionFunc,String>> allIndexReductionMethods;
  String strIndexReductionMethod;
algorithm
 allIndexReductionMethods := {(BackendDAETransform.reduceIndexDummyDer,"dummyDerivative",IndexReduction.noStateDeselection,"dummyDerivative"),
                              (IndexReduction.pantelidesIndexReduction,"Pantelites",IndexReduction.dynamicStateSelection,"dynamicStateSelection")};
 strIndexReductionMethod := getIndexReductionMethodString();
 strIndexReductionMethod := Util.getOptionOrDefault(ostrIndexReductionMethod,strIndexReductionMethod);
 IndexReductionMethod := selectIndexReductionMethod(strIndexReductionMethod,allIndexReductionMethods);
end getIndexReductionMethod;

protected function selectIndexReductionMethod
" function: selectIndexReductionMethod"
  input String strIndexReductionMethod;
  input list<tuple<Type_a,String,Type_b,String>> inIndexReductionMethods;
  output tuple<Type_a,String,Type_b,String> outIndexReductionMethod;
  replaceable type Type_a subtypeof Any;
  replaceable type Type_b subtypeof Any;
algorithm
  outIndexReductionMethod:=
  matchcontinue (strIndexReductionMethod,inIndexReductionMethods)
    local 
      String name,str;
      tuple<Type_a,String,Type_b,String> method;
      list<tuple<Type_a,String,Type_b,String>> methods;
    case (_,(method as (_,_,_,name))::methods)
      equation
        true = stringEqual(strIndexReductionMethod,name);
      then
        method;
    case (_,_::methods)
      equation
        method = selectIndexReductionMethod(strIndexReductionMethod,methods);
      then
        method;
    else
      equation
        str = stringAppendList({"Selection of Index Reduction Method ",strIndexReductionMethod," failed."});
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then   
        fail();
  end matchcontinue;
end selectIndexReductionMethod;

/*************************************************
 * matching Algorithm Selection 
 ************************************************/

public function getMatchingAlgorithmString
" function: getMatchingAlgorithmString"
  output String strMatchingAlgorithm;
algorithm
  strMatchingAlgorithm := Config.getMatchingAlgorithm();
end getMatchingAlgorithmString;

protected function getMatchingAlgorithm
" function: getIndexReductionMethod"
  input Option<String> ostrMatchingAlgorithm;
  output tuple<matchingAlgorithmFunc,String> matchingAlgorithm;
protected 
  list<tuple<matchingAlgorithmFunc,String>> allMatchingAlgorithms;
  String strMatchingAlgorithm;
algorithm
 allMatchingAlgorithms := {(BackendDAETransform.matchingAlgorithm,"omc"),
                           (Matching.BFSB,"BFSB"),
                           (Matching.DFSB,"DFSB"),
                           (Matching.MC21A,"MC21A"),
                           (Matching.PF,"PF"),
                           (Matching.PFPlus,"PFPlus"),
                           (Matching.HK,"HK"),
                           (Matching.HKDW,"HKDW"),
                           (Matching.ABMP,"ABMP"),
                           (Matching.PR_FIFO_FAIR,"PR"),
                           (Matching.DFSBExternal,"DFSBExt"),
                           (Matching.BFSBExternal,"BFSBExt"),
                           (Matching.MC21AExternal,"MC21AExt"),
                           (Matching.PFExternal,"PFExt"),
                           (Matching.PFPlusExternal,"PFPlusExt"),
                           (Matching.HKExternal,"HKExt"),
                           (Matching.HKDWExternal,"HKDWExt"),
                           (Matching.ABMPExternal,"ABMPExt"),
                           (Matching.PR_FIFO_FAIRExternal,"PRExt")};
 strMatchingAlgorithm := getMatchingAlgorithmString();
 strMatchingAlgorithm := Util.getOptionOrDefault(ostrMatchingAlgorithm,strMatchingAlgorithm);
 matchingAlgorithm := selectMatchingAlgorithm(strMatchingAlgorithm,allMatchingAlgorithms);
end getMatchingAlgorithm;

protected function selectMatchingAlgorithm
" function: selectMatchingAlgorithm"
  input String strMatchingAlgorithm;
  input list<tuple<Type_a,String>> inMatchingAlgorithms;
  output tuple<Type_a,String> outMatchingAlgorithm;
  replaceable type Type_a subtypeof Any;
algorithm
  outMatchingAlgorithm:=
  matchcontinue (strMatchingAlgorithm,inMatchingAlgorithms)
    local 
      String name,str;
      tuple<Type_a,String> method;
      list<tuple<Type_a,String>> methods;
    case (_,(method as (_,name))::methods)
      equation
        true = stringEqual(strMatchingAlgorithm,name);
      then
        method;
    case (_,_::methods)
      equation
        method = selectMatchingAlgorithm(strMatchingAlgorithm,methods);
      then
        method;
    else
      equation
        str = stringAppendList({"Selection of Matching Algorithm ",strMatchingAlgorithm," failed."});
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then   
        fail();
  end matchcontinue;
end selectMatchingAlgorithm;

/*************************************************
 * Optimisation Selection 
 ************************************************/

public function getPreOptModulesString
" function: getPreOptModulesString"
  output list<String> strPreOptModules;
algorithm
  strPreOptModules := Config.getPreOptModules();
end getPreOptModulesString;

protected function getPreOptModules
" function: getPreOptModules"
  input Option<list<String>> ostrPreOptModules;
  output list<tuple<preoptimiseDAEModule,String,Boolean>> preOptModules;
protected
  list<tuple<preoptimiseDAEModule,String,Boolean>> allPreOptModules;
  list<String> strPreOptModules;
algorithm
  allPreOptModules := {
          (BackendDAEOptimize.removeSimpleEquationsFast,"removeSimpleEquations",false),
          (BackendDAEOptimize.inlineArrayEqn,"inlineArrayEqn",false),
          (BackendDAEOptimize.evaluateFinalParameters,"evaluateFinalParameters",false),
          (BackendDAEOptimize.evaluateParameters,"evaluateParameters",false),
          (BackendDAEOptimize.removeFinalParameters,"removeFinalParameters",false),
          (BackendDAEOptimize.removeEqualFunctionCalls,"removeEqualFunctionCalls",false),
          (BackendDAEOptimize.removeProtectedParameters,"removeProtectedParameters",false),
          (BackendDAEOptimize.removeUnusedParameter,"removeUnusedParameter",false),
          (BackendDAEOptimize.removeUnusedVariables,"removeUnusedVariables",false),
          (BackendDAEOptimize.partitionIndependentBlocks,"partitionIndependentBlocks",true),
          (BackendDAEOptimize.collapseIndependentBlocks,"collapseIndependentBlocks",true),
          (BackendDAECreate.expandDerOperator,"expandDerOperator",false),
          (BackendDAEOptimize.simplifyIfEquations,"simplifyIfEquations",false),
          (BackendDAEOptimize.residualForm,"residualForm",false)
  };
  strPreOptModules := getPreOptModulesString();
  strPreOptModules := Util.getOptionOrDefault(ostrPreOptModules,strPreOptModules);
  preOptModules := selectOptModules(strPreOptModules,allPreOptModules,{});
  preOptModules := listReverse(preOptModules);
end getPreOptModules;

public function getPastOptModulesString
" function: getPreOptModulesString"
  output list<String> strPastOptModules;
algorithm
  strPastOptModules := Config.getPastOptModules();           
end getPastOptModulesString;

protected function getPastOptModules
" function: getPastOptModules"
  input Option<list<String>> ostrPastOptModules;
  output list<tuple<pastoptimiseDAEModule,String,Boolean>> pastOptModules;
protected 
  list<tuple<pastoptimiseDAEModule,String,Boolean>> allPastOptModules;
  list<String> strPastOptModules;
algorithm
  allPastOptModules := {(BackendDAEOptimize.lateInlineFunction,"lateInlineFunction",false),
  (BackendDAEOptimize.removeSimpleEquationsPast,"removeSimpleEquations",false),
  (BackendDAEOptimize.removeSimpleEquationsFast,"removeSimpleEquationsFast",false),
  (BackendDAEOptimize.removeEqualFunctionCalls,"removeEqualFunctionCalls",false),
  (BackendDAEOptimize.removeFinalParameters,"removeFinalParameters",false),
  (BackendDAEOptimize.inlineArrayEqn,"inlineArrayEqn",false),
  (BackendDAEOptimize.removeUnusedParameter,"removeUnusedParameter",false),
  (BackendDAEOptimize.removeUnusedVariables,"removeUnusedVariables",false),
  (BackendDAEOptimize.constantLinearSystem,"constantLinearSystem",false),
  (BackendDAEOptimize.tearingSystemNew,"tearingSystem",false),
  (OnRelaxation.relaxSystem,"relaxSystem",false),
  (BackendDAEOptimize.removeevaluateParameters,"removeevaluateParameters",false),
  (BackendDAEOptimize.countOperations,"countOperations",false),
  (BackendDump.dumpComponentsGraphStr,"dumpComponentsGraphStr",false),
  (BackendDAEOptimize.generateSymbolicJacobianPast,"generateSymbolicJacobian",false),
  (BackendDAEOptimize.generateSymbolicLinearizationPast,"generateSymbolicLinearization",false),
  (BackendDAEOptimize.collapseIndependentBlocks,"collapseIndependentBlocks",true),
  (BackendDAEOptimize.removeUnusedFunctions,"removeUnusedFunctions",false),
  (BackendDAEOptimize.simplifyTimeIndepFuncCalls,"simplifyTimeIndepFuncCalls",false),
  (BackendDAEOptimize.inputDerivativesUsed,"inputDerivativesUsed",false),
  (BackendDAEOptimize.simplifysemiLinear,"simplifysemiLinear",false),
  (BackendDAEOptimize.removeConstants,"removeConstants",false),
  (BackendDAEOptimize.optimizeInitialSystem,"optimizeInitialSystem",false),
  (BackendDAEOptimize.detectSparsePatternODE,"detectJacobianSparsePattern",false)
  };
  strPastOptModules := getPastOptModulesString();
  strPastOptModules := Util.getOptionOrDefault(ostrPastOptModules,strPastOptModules);
  pastOptModules := selectOptModules(strPastOptModules,allPastOptModules,{});
  pastOptModules := listReverse(pastOptModules);
end getPastOptModules;

protected function selectOptModules
" function: selectPreOptModules"
  input list<String> strOptModules;
  input list<tuple<Type_a,String,Boolean>> inOptModules;
  input list<tuple<Type_a,String,Boolean>> accumulator;
  output list<tuple<Type_a,String,Boolean>> outOptModules;
  replaceable type Type_a subtypeof Any;
algorithm
  outOptModules:=
  matchcontinue (strOptModules,inOptModules,accumulator)
    local 
      list<String> restStr;
      String strOptModul,str;
      tuple<Type_a,String,Boolean> optModule;
      list<tuple<Type_a,String,Boolean>> optModules;
    case ({},_,_) then {};
    case (_,{},_) then {};
    case (strOptModul::{},_,_)
      equation
        optModule = selectOptModules1(strOptModul,inOptModules);
      then   
        (optModule::accumulator);
    case (strOptModul::{},optModules,_)
      then   
        accumulator;
    case (strOptModul::restStr,_,_)
      equation
        optModule = selectOptModules1(strOptModul,inOptModules);
      then   
        selectOptModules(restStr,inOptModules,optModule::accumulator);
    case (strOptModul::restStr,_,_)
      equation
        str = stringAppendList({"Selection of Optimisation Module ",strOptModul," failed."});
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then   
        selectOptModules(restStr,inOptModules,accumulator);
  end matchcontinue;
end selectOptModules;

public function selectOptModules1 "
Author Frenkel TUD 2011-02"
  input String strOptModule;
  input list<tuple<Type_a,String,Boolean>> inOptModules;
  output tuple<Type_a,String,Boolean> outOptModule;
  replaceable type Type_a subtypeof Any;
algorithm
  outOptModule := matchcontinue(strOptModule,inOptModules)
    local
      Type_a a;
      String name;
      tuple<Type_a,String,Boolean> module;
      list<tuple<Type_a,String,Boolean>> rest;
    case(_,(module as (a,name,_))::rest)
      equation
        true = stringEqual(name,strOptModule);
      then
        module;
    case(_,(module as (a,name,_))::rest)
      equation
        false = stringEqual(name,strOptModule);
      then
        selectOptModules1(strOptModule,rest);
    case(_,{})
      then fail();
  end matchcontinue;
end selectOptModules1;

/*************************************************
 * profiler stuff 
 ************************************************/

public function profilerinit
algorithm
  setGlobalRoot(Global.profilerTime1Index, 0.0);
  setGlobalRoot(Global.profilerTime2Index, 0.0);
  System.realtimeTick(BackendDAE.RT_PROFILER0);
end profilerinit;

public function profilerresults
protected
   Real tg,t1,t2;
algorithm
  tg := System.realtimeTock(BackendDAE.RT_PROFILER0);
  t1 := getGlobalRoot(Global.profilerTime1Index);
  t2 := getGlobalRoot(Global.profilerTime2Index);
  print("Time all: "); print(realString(tg)); print("\n");
  print("Time t1: "); print(realString(t1)); print("\n");
  print("Time t2: "); print(realString(t2)); print("\n");
  print("Time all-t1-t2: "); print(realString(realSub(realSub(tg,t1),t2))); print("\n");
end profilerresults;

public function profilerstart1
algorithm
   System.realtimeTick(BackendDAE.RT_PROFILER1);
end profilerstart1;

public function profilerstart2
algorithm
   System.realtimeTick(BackendDAE.RT_PROFILER2);
end profilerstart2;

public function profilerstop1
protected
   Real t;
algorithm
   t := System.realtimeTock(BackendDAE.RT_PROFILER1);
   setGlobalRoot(Global.profilerTime1Index, 
     realAdd(getGlobalRoot(Global.profilerTime1Index),t));
end profilerstop1;

public function profilerstop2
protected
   Real t;
algorithm
   t := System.realtimeTock(BackendDAE.RT_PROFILER2);
   setGlobalRoot(Global.profilerTime2Index, 
     realAdd(getGlobalRoot(Global.profilerTime2Index),t));
end profilerstop2;

/*************************************************
 * traverse BackendDAE equation systems
 ************************************************/

public function mapEqSystem1
  "Helper to map a preopt module over each equation system"
  input BackendDAE.BackendDAE dae;
  input Function func;
  input A a;
  output BackendDAE.BackendDAE odae;
  partial function Function
    input BackendDAE.EqSystem syst;
    input A a;
    input BackendDAE.Shared shared;
    output BackendDAE.EqSystem osyst;
    output BackendDAE.Shared oshared;
  end Function;
  replaceable type A subtypeof Any;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs,shared) := dae;
  (systs,shared) := List.map1Fold(systs,func,a,shared);
  // Filter out empty systems
  systs := filterEmptySystems(systs);
  odae := BackendDAE.DAE(systs,shared);
end mapEqSystem1;

public function mapEqSystemAndFold1
  "Helper to map a preopt module over each equation system"
  input BackendDAE.BackendDAE dae;
  input Function func;
  input A a;
  input B initialExtra;
  output BackendDAE.BackendDAE odae;
  output B extra;
  partial function Function
    input BackendDAE.EqSystem syst;
    input A a;
    input tuple<BackendDAE.Shared,B> sharedChanged;
    output BackendDAE.EqSystem osyst;
    output tuple<BackendDAE.Shared,B> osharedChanged;
  end Function;
  replaceable type A subtypeof Any;
  replaceable type B subtypeof Any;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs,shared) := dae;
  (systs,(shared,extra)) := List.map1Fold(systs,func,a,(shared,initialExtra));
  // Filter out empty systems
  systs := filterEmptySystems(systs);
  odae := BackendDAE.DAE(systs,shared);
end mapEqSystemAndFold1;

public function mapEqSystemAndFold
  "Helper to map a preopt module over each equation system"
  input BackendDAE.BackendDAE dae;
  input Function func;
  input B initialExtra;
  output BackendDAE.BackendDAE odae;
  output B extra;
  partial function Function
    input BackendDAE.EqSystem syst;
    input tuple<BackendDAE.Shared,B> sharedChanged;
    output BackendDAE.EqSystem osyst;
    output tuple<BackendDAE.Shared,B> osharedChanged;
  end Function;
  replaceable type B subtypeof Any;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs,shared) := dae;
  (systs,(shared,extra)) := List.mapFold(systs,func,(shared,initialExtra));
  // Filter out empty systems
  systs := filterEmptySystems(systs);
  odae := BackendDAE.DAE(systs,shared);
end mapEqSystemAndFold;

public function foldEqSystem
  "Helper to map a preopt module over each equation system"
  input BackendDAE.BackendDAE dae;
  input Function func;
  input B initialExtra;
  output B extra;
  partial function Function
    input BackendDAE.EqSystem syst;
    input BackendDAE.Shared shared;
    input B fold;
    output B ofold;
  end Function;
  replaceable type B subtypeof Any;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs,shared) := dae;
  extra := List.fold1(systs,func,shared,initialExtra);
  // Filter out empty systems
  systs := filterEmptySystems(systs);
end foldEqSystem;

public function mapEqSystem
  "Helper to map a preopt module over each equation system"
  input BackendDAE.BackendDAE dae;
  input Function func;
  output BackendDAE.BackendDAE odae;
  partial function Function
    input BackendDAE.EqSystem syst;
    input BackendDAE.Shared shared;
    output BackendDAE.EqSystem osyst;
    output BackendDAE.Shared oshared;
  end Function;
protected
  list<BackendDAE.EqSystem> systs;
  BackendDAE.Shared shared;
algorithm
  BackendDAE.DAE(systs,shared) := dae;
  (systs,shared) := List.mapFold(systs,func,shared);
  // Filter out empty systems
  systs := filterEmptySystems(systs);
  odae := BackendDAE.DAE(systs,shared);
end mapEqSystem;

protected function nonEmptySystem
  input BackendDAE.EqSystem syst;
  output Boolean nonEmpty;
protected
  Integer num;
algorithm
  BackendDAE.EQSYSTEM(orderedVars=BackendDAE.VARIABLES(numberOfVars=num)) := syst;
  nonEmpty := num <> 0;
end nonEmptySystem;

public function setEqSystemMatching
  input BackendDAE.EqSystem syst;
  input BackendDAE.Matching matching;
  output BackendDAE.EqSystem osyst;
algorithm
  osyst := match (syst,matching)
    local
      BackendDAE.Variables vars;
      EquationArray eqs;
      Option<BackendDAE.IncidenceMatrix> m,mT;
    case (BackendDAE.EQSYSTEM(vars,eqs,m,mT,_),_) then BackendDAE.EQSYSTEM(vars,eqs,m,mT,matching); 
  end match;
end setEqSystemMatching;

public function filterEmptySystems
  "Filter out equation systems leaving at least one behind"
  input EqSystems systs;
  output EqSystems osysts;
algorithm
  osysts := filterEmptySystems2(List.select(systs,nonEmptySystem),systs);
end filterEmptySystems;

protected function filterEmptySystems2
  "Filter out equation systems leaving at least one behind"
  input EqSystems systs;
  input EqSystems full;
  output EqSystems olst;
algorithm
  olst := match (systs,full)
    local
      BackendDAE.EqSystem syst;
    case ({},syst::_) then {syst};
    else systs;
  end match;
end filterEmptySystems2;

public function getAllVarLst "retrieve all variables of the dae by collecting them from each equation system and combining with known vars"
  input BackendDAE.BackendDAE dae;
  output list<Var> varLst;
protected
  EqSystems eqs;
  BackendDAE.Variables knvars;
algorithm
  BackendDAE.DAE(eqs=eqs,shared = BackendDAE.SHARED(knownVars=knvars)) := dae;
  varLst := List.flatten(List.map(listAppend({knvars},List.map(eqs,BackendVariable.daeVars)),varList));  
end getAllVarLst;

public function getAlgorithms
  input BackendDAE.BackendDAE dae;
  output array<DAE.Algorithm> algs;
protected
  BackendDAE.EqSystems systs;
  list<DAE.Algorithm> alglst;
algorithm
  BackendDAE.DAE(eqs=systs) := dae;
  alglst := List.fold(systs,collectAlgorithmsFromEqSystem,{});
  algs := listArray(alglst);
end getAlgorithms;

protected function collectAlgorithmsFromEqSystem
  input BackendDAE.EqSystem syst;
  input list<DAE.Algorithm> alglst;
  output list<DAE.Algorithm> oalglst;
protected 
  BackendDAE.EquationArray eqns;
algorithm
  BackendDAE.EQSYSTEM(orderedEqs=eqns) := syst;
  oalglst := BackendEquation.traverseBackendDAEEqns(eqns,collectAlgorithms,alglst);
end collectAlgorithmsFromEqSystem;

protected function collectAlgorithms
  input tuple<BackendDAE.Equation, list<DAE.Algorithm>> inTpl;
  output tuple<BackendDAE.Equation, list<DAE.Algorithm>> outTpl;
algorithm
  outTpl := match(inTpl)
    local
      BackendDAE.Equation eqn;
      DAE.Algorithm alg;
      list<DAE.Algorithm> alglst;
    case ((eqn as BackendDAE.ALGORITHM(alg=alg),alglst))
      then
        ((eqn,alg::alglst));
    else
      then
        inTpl;
  end match;
end collectAlgorithms;




/*
 * inital system
 *
 */
protected function analyzeInitialSystem "protected function analyzeInitialSystem
  author: lochel"
  input BackendDAE.EqSystem inSystem;
  input BackendDAE.BackendDAE inDAE;  // original DAE
  output BackendDAE.EqSystem outSystem;
protected
BackendDAE.EqSystem system;
  BackendDAE.IncidenceMatrix m, mt;
algorithm
  (system, m, mt) := getIncidenceMatrix(inSystem, BackendDAE.NORMAL());
  system := analyzeInitialSystem1(system, mt, 1); // remove unneeded pre-vars
  system := analyzeInitialSystem2(system, inDAE); // fix unbalanced initial system
  (outSystem, _, _) := getIncidenceMatrix(system, BackendDAE.NORMAL());
end analyzeInitialSystem;

protected function analyzeInitialSystem1 "protected function analyzeInitialSystem1
  author: lochel"
  input BackendDAE.EqSystem inSystem;
  input BackendDAE.IncidenceMatrix inMT;    // IncidenceMatrix = array<list<IncidenceMatrixElementEntry>>;
  input Integer inI;                        // current row (var-index)
  output BackendDAE.EqSystem outSystem;
algorithm
  outSystem := matchcontinue(inSystem, inMT, inI)
    local
      BackendDAE.EqSystem system;
      Integer nVars;
      Integer nIncidences;
      BackendDAE.Variables vars;
      BackendDAE.Var var;
      DAE.ComponentRef cr;
      Option<DAE.Exp> startValue;
      BackendDAE.EquationArray orderedEqs "orderedEqs ; ordered Equations" ;
      
      BackendDAE.Equation eqn;
      DAE.Exp e, crExp, startExp;
      DAE.Type tp;
      String crStr;
      
    case (BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=orderedEqs), _, _) equation
      nVars = arrayLength(inMT);
      true = intGt(inI, nVars);
      
      vars = BackendVariable.compressVariables(vars);
      system = BackendDAE.EQSYSTEM(vars, orderedEqs, NONE(), NONE(), BackendDAE.NO_MATCHING());
    then system;
    
    case (_, _, _) equation
      nIncidences = listLength(inMT[inI]);
      true = intGt(nIncidences, 0);
      system = analyzeInitialSystem1(inSystem, inMT, inI+1);
    then system;
    
    case (BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=orderedEqs), _, _) equation
      true = Flags.isSet(Flags.PEDANTIC);
      
      var = BackendVariable.getVarAt(vars, inI);
      cr = BackendVariable.varCref(var);
      crStr = ComponentReference.crefStr(cr);
      
      true = intEq(0, System.strncmp(crStr, DAE.preNamePrefix, stringLength(DAE.preNamePrefix)));
      
      Error.addCompilerWarning("Following pre-variable does not appear in any of the equations of the initialization system. It will be removed: " +& crStr);
      
      (vars, var) = BackendVariable.removeVar(inI, vars);
      system = BackendDAE.EQSYSTEM(vars, orderedEqs, NONE(), NONE(), BackendDAE.NO_MATCHING());
      system = analyzeInitialSystem1(system, inMT, inI+1);
    then system;
    
    case (BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=orderedEqs), _, _) equation
      true = Flags.isSet(Flags.PEDANTIC);
      
      var = BackendVariable.getVarAt(vars, inI);
      cr = BackendVariable.varCref(var);
      crStr = ComponentReference.crefStr(cr);
      
      false = intEq(0, System.strncmp(crStr, DAE.preNamePrefix, stringLength(DAE.preNamePrefix)));
      
      Error.addCompilerWarning("Following variable does not appear in any of the equations of the initialization system: " +& crStr);
    then fail();
    
    case (BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=orderedEqs), _, _) equation
      false = Flags.isSet(Flags.PEDANTIC);
      
      (vars, var) = BackendVariable.removeVar(inI, vars);
      system = BackendDAE.EQSYSTEM(vars, orderedEqs, NONE(), NONE(), BackendDAE.NO_MATCHING());
      system = analyzeInitialSystem1(system, inMT, inI+1);
    then system;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/BackendDAEUtil.mo: function analyzeInitialSystem1 failed"});
    then fail();
  end matchcontinue;
end analyzeInitialSystem1;

protected function analyzeInitialSystem2 "function analyzeInitialSystem2
  author lochel"
  input BackendDAE.EqSystem inSystem;
  input BackendDAE.BackendDAE inDAE;  // original DAE
  output BackendDAE.EqSystem outSystem;
algorithm
  outSystem := matchcontinue(inSystem, inDAE)
    local
      BackendDAE.EqSystem system;
      list<tuple<pastoptimiseDAEModule, String, Boolean>> pastOptModules;
      tuple<StructurallySingularSystemHandlerFunc, String, stateDeselectionFunc, String> daeHandler;
      tuple<matchingAlgorithmFunc, String> matchingAlgorithm;
      Integer nVars, nEqns;
      BackendDAE.Variables vars;
      BackendDAE.EquationArray eqns;
      
    // over-determined system
    case(BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns), _) equation
      nVars = BackendVariable.varsSize(vars);
      nEqns = equationSize(eqns);
      true = intGt(nEqns, nVars);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "Trying to fix over-determined initial system... [not implemented yet!]");
    then fail();
    
    // under-determined system  
    case(BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns), _) equation
      nVars = BackendVariable.varsSize(vars);
      nEqns = equationSize(eqns);
      true = intLt(nEqns, nVars);
      
      (true, vars, eqns) = fixUnderDeterminedInitialSystem(inDAE, vars, eqns);
      
      system = BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING());
    then system;
    
    case (_, _)
    then inSystem;
  end matchcontinue;
end analyzeInitialSystem2;

public function solveInitialSystem "function solveInitialSystem
  author Frenkel TUD 2012-10"
  input BackendDAE.BackendDAE inDAE;
  output BackendDAE.BackendDAE outDAE;
  output BackendDAE.BackendDAE outInitDAE;
algorithm
  (outDAE, outInitDAE) := match(inDAE)
    local
      BackendDAE.EqSystems systs;
      BackendDAE.Variables knvars, vars, fixvars, evars, eavars;
      BackendDAE.EquationArray inieqns, eqns, emptyeqns, reeqns;
      BackendDAE.EqSystem initsyst;
      BackendDAE.BackendDAE initdae;
      Env.Cache cache;
      Env.Env env;
      DAE.FunctionTree functionTree;
      list<BackendDAE.Equation> eqnslst;
      array<DAE.Constraint> constraints;
      array<DAE.ClassAttributes> classAttrs;
      
    case(BackendDAE.DAE(systs, BackendDAE.SHARED(knownVars=knvars,
                                                 initialEqs=inieqns,
                                                 constraints=constraints,
                                                 classAttrs=classAttrs,
                                                 cache=cache,
                                                 env=env,
                                                 functionTree=functionTree))) equation
      // collect vars for initial system
      vars = emptyVars();
      fixvars = emptyVars();
      ((vars, fixvars)) = BackendVariable.traverseBackendDAEVars(knvars, collectInitialVars, (vars, fixvars));
      
      // collect eqns for initial system
      ((eqns, reeqns)) = BackendEquation.traverseBackendDAEEqns(inieqns, collectInitialEqns, (listEquation({}), listEquation({})));
      ((vars, fixvars, eqns, reeqns)) = List.fold(systs, collectInitialVarsEqnsSystem, ((vars, fixvars, eqns, reeqns)));
      
      // generate initial system
      initsyst = BackendDAE.EQSYSTEM(vars, eqns, NONE(), NONE(), BackendDAE.NO_MATCHING());
      initsyst = analyzeInitialSystem(initsyst, inDAE);      
      (initsyst, _, _) = getIncidenceMatrix(initsyst, BackendDAE.NORMAL());
      BackendDAE.EQSYSTEM(vars, eqns, _, _, _) = initsyst;

      evars = emptyVars();
      eavars = emptyVars();
      emptyeqns = listEquation({});
      initdae = BackendDAE.DAE({initsyst},
                               BackendDAE.SHARED(fixvars,
                                                 evars,
                                                 eavars,
                                                 emptyeqns,
                                                 reeqns,
                                                 constraints,
                                                 classAttrs,
                                                 cache,
                                                 env,
                                                 functionTree,
                                                 BackendDAE.EVENT_INFO({},{},{},{},0),
                                                 {},
                                                 BackendDAE.INITIALSYSTEM(),
                                                 {}));

      // some debug prints
      Debug.fcall(Flags.DUMP_INITIAL_SYSTEM, print, "Initial System:\n");
      Debug.fcall(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dump, initdae);
      
      // now let's solve the system!
      initdae = solveInitialSystem1(vars, eqns, inDAE, initdae);
    then(inDAE, initdae);
  end match;
end solveInitialSystem;

protected function solveInitialSystem1 "function solveInitialSystem1
  author Frenkel TUD 2012-10"
  input BackendDAE.Variables inVars;
  input BackendDAE.EquationArray inEqns;
  input BackendDAE.BackendDAE inDAE;
  input BackendDAE.BackendDAE inInitDAE;
  output BackendDAE.BackendDAE outDAE;
algorithm
  outDAE := matchcontinue(inVars, inEqns, inDAE, inInitDAE)
    local
      BackendDAE.BackendDAE isyst;
      list<tuple<pastoptimiseDAEModule, String, Boolean>> pastOptModules;
      tuple<StructurallySingularSystemHandlerFunc, String, stateDeselectionFunc, String> daeHandler;
      tuple<matchingAlgorithmFunc, String> matchingAlgorithm;
      Integer nVars, nEqns;
      BackendDAE.Variables vars;
      BackendDAE.EquationArray eqns;
      
    // over-determined system
    case(vars, eqns, _, _) equation
      nVars = BackendVariable.varsSize(vars);
      nEqns = equationSize(eqns);
      true = intGt(nEqns, nVars);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "It was not possible to solve the over-determined initial system.");
    then fail();
    
    // equal  
    case(vars, eqns, _, _) equation
      nVars = BackendVariable.varsSize(vars);
      nEqns = equationSize(eqns);
      true = intEq(nEqns, nVars);
      
      pastOptModules = getPastOptModules(SOME({"constantLinearSystem", /* here we need a special case and remove only alias and constant (no variables of the system) variables "removeSimpleEquations", */ "tearingSystem"}));
      matchingAlgorithm = getMatchingAlgorithm(NONE());
      daeHandler = getIndexReductionMethod(NONE());
      
      // solve system
      isyst = transformBackendDAE(inInitDAE, SOME((BackendDAE.NO_INDEX_REDUCTION(), BackendDAE.EXACT())), NONE(), NONE());
      
      // simplify system
      (isyst,Util.SUCCESS()) = pastoptimiseDAE(isyst, pastOptModules, matchingAlgorithm, daeHandler);
      Debug.fcall(Flags.DUMP_INITIAL_SYSTEM, print, "Solved Initial System:\n");
      Debug.fcall(Flags.DUMP_INITIAL_SYSTEM, BackendDump.dump, isyst);
    then isyst;
    
    // under-determined system  
    case(_, _, _, _) equation
      nVars = BackendVariable.varsSize(inVars);
      nEqns = equationSize(inEqns);
      true = intLt(nEqns, nVars);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "It was not possible to solve the under-determined initial system.");
    then fail();
  end matchcontinue;
end solveInitialSystem1;

protected function fixUnderDeterminedInitialSystem "protected function fixUnderDeterminedInitialSystem
  author: lochel"
  input BackendDAE.BackendDAE inDAE;
  input BackendDAE.Variables inVars;
  input BackendDAE.EquationArray inEqns;
  output Boolean outFixed;
  output BackendDAE.Variables outVars;
  output BackendDAE.EquationArray outEqns;
algorithm
  (outFixed, outVars, outEqns) := matchcontinue(inDAE, inVars, inEqns)
    local
      BackendDAE.SymbolicJacobian jacG;
      BackendDAE.SparsePattern sparsityPattern;     // type SparsePattern = tuple<list<tuple< .DAE.ComponentRef, list< .DAE.ComponentRef>>>,  // column-wise sparse pattern
                                                    //                            tuple<list< .DAE.ComponentRef>,                             // diff vars
                                                    //                                  list< .DAE.ComponentRef>>>;                           // diffed vars
      BackendDAE.BackendDAE dae;
      
      .DAE.ComponentRef cr;
      list< .DAE.ComponentRef> diffVars, diffedVars;
      String str;
      list<BackendDAE.Var> vars;    // all vars
      list<BackendDAE.Var> outputs; // $res1 ... $resN (initial equations)
      list<BackendDAE.Var> states;
      BackendDAE.EqSystems systs;
      BackendDAE.Variables ivars;
      Integer nVars, nStates, nEqns;
      BackendDAE.EquationArray eqns;
      
    case(_, _, eqns) equation
      (dae, outputs) = BackendDAEOptimize.generateInitialMatricesDAE(inDAE);
      
      vars = varList(inVars);
      (sparsityPattern, _) = BackendDAEOptimize.generateSparsePattern(dae, vars, outputs);
      
      BackendDAE.DAE(eqs=systs) = inDAE;
      ivars = emptyVars();
      ivars = List.fold(systs, collectUnfixedStatesFromSystem, ivars);
      states = varList(ivars);

      nStates = BackendVariable.varsSize(ivars);
      nVars = BackendVariable.varsSize(inVars);
      nEqns = equationSize(eqns);
      true = intEq(nVars, nEqns+nStates);
      
      Debug.fcall(Flags.PEDANTIC, Error.addCompilerWarning, "Setting all (" +& intString(nStates) +& ") states to fixed=true to solve the initial system.");

      eqns = addStartValueEquations(states, eqns);
    then (true, inVars, eqns);
    
    else
    then (false, inVars, inEqns);
  end matchcontinue;
end fixUnderDeterminedInitialSystem;

protected function addStartValueEquations "function addStartValueEquations
  author lochel"
  input list<BackendDAE.Var> inVars;
  input BackendDAE.EquationArray inEqns;
  output BackendDAE.EquationArray outEqns;
algorithm
  outEqns := matchcontinue(inVars, inEqns)
    local
      BackendDAE.Var var;
      list<BackendDAE.Var> vars;
      BackendDAE.Equation eqn;
      BackendDAE.EquationArray eqns;
      
      DAE.Exp e, e1, crefExp, startExp;
      DAE.ComponentRef cref;
      DAE.Type tp;
      
    case ({}, _)
    then inEqns;
    
    case (var::vars, eqns) equation
      cref = BackendVariable.varCref(var);
      crefExp = DAE.CREF(cref, DAE.T_REAL_DEFAULT);
      
      e = Expression.crefExp(cref);
      tp = Expression.typeof(e);
      startExp = Expression.makeBuiltinCall("$_start", {e}, tp);
      
      eqn = BackendDAE.EQUATION(crefExp, startExp, DAE.emptyElementSource);
      
      eqns = BackendEquation.equationAdd(eqn, eqns);
      eqns = addStartValueEquations(vars, eqns);
    then eqns;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/BackendDAEUtil.mo: function addStartValueEquations failed"});
    then fail();
  end matchcontinue;
end addStartValueEquations;

protected function collectInitialVarsEqnsSystem "function collectInitialVarsEqnsSystem
  author Frenkel TUD 2012-10"
  input BackendDAE.EqSystem isyst;
  input tuple<BackendDAE.Variables, BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.EquationArray> iTpl;
  output tuple<BackendDAE.Variables, BackendDAE.Variables, BackendDAE.EquationArray, BackendDAE.EquationArray> oTpl;
algorithm
  oTpl := match(isyst, iTpl)
    local
      BackendDAE.Variables vars, ivars, fixvars;
      BackendDAE.EquationArray eqns, ieqns, reqns;
    case (BackendDAE.EQSYSTEM(orderedVars=vars, orderedEqs=eqns), (ivars, fixvars, ieqns, reqns)) equation
      // collect vars for initial system
      ((ivars, fixvars)) = BackendVariable.traverseBackendDAEVars(vars, collectInitialVars, (ivars, fixvars));
      
      // collect eqns for initial system
      ((ieqns, reqns)) = BackendEquation.traverseBackendDAEEqns(eqns, collectInitialEqns, (ieqns, reqns));
    then ((ivars, fixvars, ieqns, reqns));
  end match;
end collectInitialVarsEqnsSystem;

protected function collectUnfixedStatesFromSystem
  input BackendDAE.EqSystem isyst;
  input BackendDAE.Variables inVars;
  output BackendDAE.Variables outVars;
algorithm
  outVars := match(isyst, inVars)
    local
      BackendDAE.Variables vars, ivars;
    case (BackendDAE.EQSYSTEM(orderedVars=vars), ivars) equation
      // collect vars for initial system
      ivars = BackendVariable.traverseBackendDAEVars(vars, collectUnfixedStates, ivars);
    then ivars;
  end match;
end collectUnfixedStatesFromSystem;

protected function collectUnfixedStates
  input tuple<BackendDAE.Var, BackendDAE.Variables> inTpl;
  output tuple<BackendDAE.Var, BackendDAE.Variables> outTpl;
algorithm
  outTpl := matchcontinue(inTpl)
    local
      BackendDAE.Var var, preVar, derVar;
      BackendDAE.Variables vars, fixvars;
      DAE.ComponentRef cr, preCR, derCR;
      Boolean isFixed;
      DAE.Type ty;
      DAE.InstDims arryDim;
      Option<DAE.Exp> startValue;
    
    // state
    case((var as BackendDAE.VAR(varKind=BackendDAE.STATE()), vars)) equation
      false = BackendVariable.varFixed(var);
      vars = BackendVariable.addVar(var, vars);
    then ((var, vars));
    
    else
    then inTpl;
  end matchcontinue;
end collectUnfixedStates;

protected function collectInitialVars "protected function collectInitialVars
  This function collects all the vars for the initial system."
  input tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables>> inTpl;
  output tuple<BackendDAE.Var, tuple<BackendDAE.Variables, BackendDAE.Variables>> outTpl;
algorithm
  outTpl := match(inTpl)
    local
      BackendDAE.Var var, preVar, derVar;
      BackendDAE.Variables vars, fixvars;
      DAE.ComponentRef cr, preCR, derCR;
      Boolean isFixed;
      DAE.Type ty;
      DAE.InstDims arryDim;
      Option<DAE.Exp> startValue;
    
    // state
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.STATE(), bindExp=NONE(), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      
      derCR = ComponentReference.crefPrefixDer(cr);  // cr => $DER.cr
      derVar = BackendDAE.VAR(derCR, BackendDAE.VARIABLE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      
      vars = BackendVariable.addVar(derVar, vars);
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, var, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, var, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    // state with binding
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.STATE(), bindExp=NONE(), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      derCR = ComponentReference.crefPrefixDer(cr);  // cr => $DER.cr
      derVar = BackendDAE.VAR(derCR, BackendDAE.VARIABLE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      vars = BackendVariable.addVar(derVar, vars);
    then ((var, (vars, fixvars)));
    
    // discrete
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.DISCRETE(), bindExp=NONE(), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      startValue = BackendVariable.varStartValueOption(var);
      
      var = BackendVariable.setVarFixed(var, false);
      
      preCR = ComponentReference.crefPrefixPre(cr);  // cr => $PRE.cr
      preVar = BackendDAE.VAR(preCR, BackendDAE.DISCRETE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      preVar = BackendVariable.setVarFixed(preVar, isFixed);
      preVar = BackendVariable.setVarStartValueOption(preVar, startValue);
      
      vars = BackendVariable.addVar(var, vars);
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, preVar, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, preVar, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    // discrete with binding
    case((var as BackendDAE.VAR(varName=cr, varKind=BackendDAE.DISCRETE(), bindExp=SOME(_), varType=ty, arryDim=arryDim), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      startValue = BackendVariable.varStartValueOption(var);
      
      preCR = ComponentReference.crefPrefixPre(cr);  // cr => $PRE.cr
      preVar = BackendDAE.VAR(preCR, BackendDAE.DISCRETE(), DAE.BIDIR(), DAE.NON_PARALLEL(), ty, NONE(), NONE(), arryDim, DAE.emptyElementSource, NONE(), NONE(), DAE.NON_CONNECTOR());
      preVar = BackendVariable.setVarFixed(preVar, isFixed);
      preVar = BackendVariable.setVarStartValueOption(preVar, startValue);
      
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, preVar, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, preVar, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    // parameter
    case((var as BackendDAE.VAR(varKind=BackendDAE.PARAM(), bindExp=NONE()), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      var = BackendVariable.setVarKind(var, BackendDAE.VARIABLE());
      
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, var, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, var, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    case((var as BackendDAE.VAR(bindExp=NONE()), (vars, fixvars))) equation
      isFixed = BackendVariable.varFixed(var);
      
      vars = Debug.bcallret2(not isFixed, BackendVariable.addVar, var, vars, vars);
      fixvars = Debug.bcallret2(isFixed, BackendVariable.addVar, var, fixvars, fixvars);
    then ((var, (vars, fixvars)));
    
    else
    then inTpl;
  end match;
end collectInitialVars;

protected function generateInitialWhenEqn "public function generateInitialWhenEqn
  author: lochel
  This function generates out of a given when-equation, a equation for the initialization-problem."
  input BackendDAE.Equation inEqn;
  output BackendDAE.Equation outEqn;
algorithm
  outEqn := matchcontinue(inEqn)
    local
      .DAE.Exp condition        "The when-condition" ;
      .DAE.ComponentRef left    "Left hand side of equation" ;
      .DAE.Exp right            "Right hand side of equation" ;
      .DAE.ElementSource source "origin of equation";
      BackendDAE.Equation eqn;
      .DAE.Type identType;
      .DAE.ComponentRef preCR;
      
    // active when equation during initialization
    case BackendDAE.WHEN_EQUATION(whenEquation=BackendDAE.WHEN_EQ(condition=condition, left=left, right=right), source=source) equation
      true = Expression.containsInitialCall(condition, false);  // do not use Expression.traverseExp
      identType = ComponentReference.crefType(left);
      eqn = BackendDAE.EQUATION(DAE.CREF(left, identType), right, source);
    then eqn;
    
    // inactive when equation during initialization
    case BackendDAE.WHEN_EQUATION(whenEquation=BackendDAE.WHEN_EQ(condition=condition, left=left, right=right), source=source) equation
      identType = ComponentReference.crefType(left);
      preCR = ComponentReference.crefPrefixPre(left);
      eqn = BackendDAE.EQUATION(DAE.CREF(left, identType), DAE.CREF(preCR, identType), source);
    then eqn;
    
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/BackendDAEUtil.mo: function generateInitialWhenEqn failed"});
    then fail();
  end matchcontinue;
end generateInitialWhenEqn;

protected function collectInitialEqns
  input tuple<BackendDAE.Equation, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> inTpl;
  output tuple<BackendDAE.Equation, tuple<BackendDAE.EquationArray,BackendDAE.EquationArray>> outTpl;
protected
  BackendDAE.Equation eqn, eqn1;
  BackendDAE.EquationArray eqns, reeqns;
  Integer size;
  Boolean b, isWhenEquation;
algorithm
  (eqn, (eqns, reeqns)) := inTpl;
  
  // replace der(x) with $DER.x and replace pre(x) with $PRE.x
  (eqn1, _) := BackendEquation.traverseBackendDAEExpsEqn(eqn, replaceDerPreCref, 0);
  
  // traverse when equations
  isWhenEquation := BackendEquation.isWhenEquation(eqn);
  eqn1 := Debug.bcallret1(isWhenEquation, generateInitialWhenEqn, eqn1, eqn1);
  
  // add it, if size is zero (terminate,assert,noretcall) move to removed equations
  size := BackendEquation.equationSize(eqn1);
  b := intGt(size, 0);
  
  eqns := Debug.bcallret2(b, BackendEquation.equationAdd, eqn1, eqns, eqns);
  reeqns := Debug.bcallret2(not b, BackendEquation.equationAdd, eqn1, reeqns, reeqns);
  outTpl := (eqn, (eqns, reeqns));
end collectInitialEqns;

protected function replaceDerPreCref "function replaceDerPreCref
  author: Frenkel TUD 2011-05
  helper for collectInitialEqns"
  input tuple<DAE.Exp, Integer> inExp;
  output tuple<DAE.Exp, Integer> outExp;
protected
   DAE.Exp e;
   Integer i;  
algorithm
  (e, i) := inExp;
  outExp := Expression.traverseExp(e, replaceDerPreCrefExp, i);
end replaceDerPreCref;

protected function replaceDerPreCrefExp "function replaceDerPreCrefExp
  author: Frenkel TUD 2011-05
  helper for replaceDerCref"
  input tuple<DAE.Exp, Integer> inExp;
  output tuple<DAE.Exp, Integer> outExp;
algorithm
  (outExp) := matchcontinue(inExp)
    local
      DAE.ComponentRef dummyder, cr;
      DAE.Type ty;
      Integer i;

    case ((DAE.CALL(path = Absyn.IDENT(name = "der"), expLst = {DAE.CREF(componentRef = cr)}, attr=DAE.CALL_ATTR(ty=ty)), i)) equation
      dummyder = ComponentReference.crefPrefixDer(cr);
    then ((DAE.CREF(dummyder, ty), i+1));
    
    case ((DAE.CALL(path = Absyn.IDENT(name = "pre"), expLst = {DAE.CREF(componentRef = cr)}, attr=DAE.CALL_ATTR(ty=ty)), i)) equation
      dummyder = ComponentReference.crefPrefixPre(cr);
    then ((DAE.CREF(dummyder, ty), i+1));
      
    else
    then inExp;
  end matchcontinue;
end replaceDerPreCrefExp;

end BackendDAEUtil;
