/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */
/*
 *
 * @author Martin Sjölund <martin.sjolund@liu.se>
 *
 * RCS: $Id$
 *
 */

#include <QDebug>
#include <QXmlStreamReader>
#include "OMDumpXML.h"

const char* OMEquationTypeToString(int t)
{
  static const char *kindToString[equationTypeSize] = {"start","parameter","initial","regular"};
  return kindToString[t];
}

QString OMOperation::toString()
{
  return "unknown operation";
}

OMOperationSimplify::OMOperationSimplify(QStringList ops)
{
  before = ops.size() > 0 ? ops[0] : "";
  after = ops.size() > 1 ? ops[1] : "";
}

QString OMOperationSimplify::toString()
{
  return "simplify: " + before + " => " + after;
}

OMOperationScalarize::OMOperationScalarize(int _index, QStringList ops)
{
  index = _index;
  before = ops.size() > 0 ? ops[0] : "";
  after = ops.size() > 1 ? ops[1] : "";
}

QString OMOperationScalarize::toString()
{
  return QString("scalarize(%1): %2 => %3").arg(index).arg(before).arg(after);
}

OMOperationInline::OMOperationInline(QStringList ops)
{
  before = ops.size() > 0 ? ops[0] : "";
  after = ops.size() > 1 ? ops[1] : "";
}

QString OMOperationInline::toString()
{
  return "inline: " + before + " => " + after;
}

OMOperationSubstitution::OMOperationSubstitution(QStringList ops)
{
  before = ops.takeFirst();
  substitutions = ops;
}

QString OMOperationSubstitution::toString()
{
  return "substitute: " + before + " => " + substitutions.join(" => ");
}

OMOperationSolved::OMOperationSolved(QStringList ops)
{
  lhs = ops.size() > 0 ? ops[0] : "";
  rhs = ops.size() > 1 ? ops[1] : "";
}

QString OMOperationSolved::toString()
{
  return "solved: " + lhs + " = " + rhs;
}

OMOperationLinearSolved::OMOperationLinearSolved(QStringList ops)
{
  text = ops.size() > 0 ? ops[0] : "";
}

QString OMOperationLinearSolved::toString()
{
  return "linear-solved: " + text;
}

OMOperationSolve::OMOperationSolve(QStringList ops)
{
  lhs_old = ops.size() > 0 ? ops[0] : "";
  rhs_old = ops.size() > 1 ? ops[1] : "";
  lhs_new = ops.size() > 2 ? ops[2] : "";
  rhs_new = ops.size() > 3 ? ops[3] : "";
}

QString OMOperationSolve::toString()
{
  return "solve: " + lhs_old + " = " + rhs_old + " => " + lhs_new + " = " + rhs_new;
}

OMOperationDifferentiate::OMOperationDifferentiate(QStringList ops)
{
  exp = ops.size() > 0 ? ops[0] : "";
  wrt = ops.size() > 1 ? ops[1] : "";
  result = ops.size() > 2 ? ops[2] : "";
}

QString OMOperationDifferentiate::toString()
{
  return "differentiate: d/d" + wrt + " " + exp + " => " + result;
}

OMOperationResidual::OMOperationResidual(QStringList ops)
{
  lhs = ops.size() > 0 ? ops[0] : "";
  rhs = ops.size() > 1 ? ops[1] : "";
  result = ops.size() > 2 ? ops[2] : "";
}

QString OMOperationResidual::toString()
{
  return "residual: " + lhs + " = " + rhs + " => 0 = " + result;
}

OMOperationFlattening::OMOperationFlattening(QStringList ops)
{
  original = ops.size() > 0 ? ops[0] : "";
  flattened = ops.size() > 1 ? ops[1] : "";
}

QString OMOperationFlattening::toString()
{
  return "original: " + original + " => flattened: " + flattened;
}

OMOperationDummyDerivative::OMOperationDummyDerivative(QStringList ops)
{
  chosen = ops.takeFirst();
  candidates = ops;
}

QString OMOperationDummyDerivative::toString()
{
  return "dummy derivative: " + chosen + ", not chosen " + candidates.join(",");
}

OMInfo::OMInfo()
{
  isValid = false;
}

QString OMInfo::toString() {
  QString result;
  QTextStream(&result) << "[" << file << ":" << lineStart << ":" << colStart << "-" << lineEnd << ":" << colEnd << "]";
  return result;
}

OMVariable::OMVariable()
{

}

OMVariable::OMVariable(const OMVariable &var)
{
  name = var.name;
  comment = var.comment;
  info = var.info;
  types = var.types;
  for (int i = 0; i < equationTypeSize ; i++)
  {
    definedIn[i] = var.definedIn[i];
    usedIn[i] = var.usedIn[i];
  }
  foreach (OMOperation *op, var.ops) {
    if (dynamic_cast<OMOperationSimplify*>(op))
      ops.append(new OMOperationSimplify(*dynamic_cast<OMOperationSimplify*>(op)));
    else if (dynamic_cast<OMOperationScalarize*>(op))
      ops.append(new OMOperationScalarize(*dynamic_cast<OMOperationScalarize*>(op)));
    else if (dynamic_cast<OMOperationInline*>(op))
      ops.append(new OMOperationInline(*dynamic_cast<OMOperationInline*>(op)));
    else if (dynamic_cast<OMOperationSubstitution*>(op))
      ops.append(new OMOperationSubstitution(*dynamic_cast<OMOperationSubstitution*>(op)));
    else if (dynamic_cast<OMOperationSolved*>(op))
      ops.append(new OMOperationSolved(*dynamic_cast<OMOperationSolved*>(op)));
    else if (dynamic_cast<OMOperationLinearSolved*>(op))
      ops.append(new OMOperationLinearSolved(*dynamic_cast<OMOperationLinearSolved*>(op)));
    else if (dynamic_cast<OMOperationSolve*>(op))
      ops.append(new OMOperationSolve(*dynamic_cast<OMOperationSolve*>(op)));
    else if (dynamic_cast<OMOperationDifferentiate*>(op))
      ops.append(new OMOperationDifferentiate(*dynamic_cast<OMOperationDifferentiate*>(op)));
    else if (dynamic_cast<OMOperationResidual*>(op))
      ops.append(new OMOperationResidual(*dynamic_cast<OMOperationResidual*>(op)));
    else if (dynamic_cast<OMOperationDummyDerivative*>(op))
      ops.append(new OMOperationDummyDerivative(*dynamic_cast<OMOperationDummyDerivative*>(op)));
    else if (dynamic_cast<OMOperationFlattening*>(op))
      ops.append(new OMOperationFlattening(*dynamic_cast<OMOperationFlattening*>(op)));
    else
      ops.append(new OMOperation(*op));
  }
}

OMVariable::~OMVariable() {
  foreach (OMOperation *op, ops) {
    delete op;
  }
}

OMEquation::OMEquation()
{

}

OMEquation::OMEquation(const OMEquation &eq)
{
  kind = eq.kind;
  index = eq.index;
  text = eq.text;
  info = eq.info;
  defines = eq.defines;
  depends = eq.depends;
  foreach (OMOperation *op, eq.ops) {
    if (dynamic_cast<OMOperationSimplify*>(op))
      ops.append(new OMOperationSimplify(*dynamic_cast<OMOperationSimplify*>(op)));
    else if (dynamic_cast<OMOperationScalarize*>(op))
      ops.append(new OMOperationScalarize(*dynamic_cast<OMOperationScalarize*>(op)));
    else if (dynamic_cast<OMOperationInline*>(op))
      ops.append(new OMOperationInline(*dynamic_cast<OMOperationInline*>(op)));
    else if (dynamic_cast<OMOperationSubstitution*>(op))
      ops.append(new OMOperationSubstitution(*dynamic_cast<OMOperationSubstitution*>(op)));
    else if (dynamic_cast<OMOperationSolved*>(op))
      ops.append(new OMOperationSolved(*dynamic_cast<OMOperationSolved*>(op)));
    else if (dynamic_cast<OMOperationLinearSolved*>(op))
      ops.append(new OMOperationLinearSolved(*dynamic_cast<OMOperationLinearSolved*>(op)));
    else if (dynamic_cast<OMOperationSolve*>(op))
      ops.append(new OMOperationSolve(*dynamic_cast<OMOperationSolve*>(op)));
    else if (dynamic_cast<OMOperationDifferentiate*>(op))
      ops.append(new OMOperationDifferentiate(*dynamic_cast<OMOperationDifferentiate*>(op)));
    else if (dynamic_cast<OMOperationResidual*>(op))
      ops.append(new OMOperationResidual(*dynamic_cast<OMOperationResidual*>(op)));
    else if (dynamic_cast<OMOperationDummyDerivative*>(op))
      ops.append(new OMOperationDummyDerivative(*dynamic_cast<OMOperationDummyDerivative*>(op)));
    else if (dynamic_cast<OMOperationFlattening*>(op))
      ops.append(new OMOperationFlattening(*dynamic_cast<OMOperationFlattening*>(op)));
    else
      ops.append(new OMOperation(*op));
  }
  eqs = eq.eqs;
}

OMEquation::~OMEquation() {
  foreach (OMOperation *op, ops) {
    delete op;
  }
}

QString OMEquation::toString()
{
  if (text.size() < 1) {
    return "(dummy equation)";
  } else if (text[0] == "assign") {
    return QString("(assignment) %1 = %2").arg(defines[0]).arg(text[1]);
  } else if (text[0] == "statement") {
    return "(statement) " + text[1];
  } else {
    return "(" + text.join(",") + ")";
  }
}

MyHandler::MyHandler(QFile &file)
{
  hasOperationsEnabled = false;
  QXmlSimpleReader xmlReader;
  QXmlInputSource *source = new QXmlInputSource(&file);
  xmlReader.setContentHandler(this);
  xmlReader.setErrorHandler(this);
  bool ok = xmlReader.parse(source);
  delete source;
  if (!ok) {
    throw QString("Parsing failed: %1").arg(file.fileName());
  }
}

MyHandler::~MyHandler()
{
  foreach (OMEquation *eq, equations) {
    delete eq;
  }
}

OMEquation* MyHandler::getOMEquation(int index)
{
  for (int i = 1 ; i < equations.size() ; i++) {
    if (equations[i]->index == index)
      return equations[i];
  }
  return NULL;
}

bool MyHandler::startDocument()
{
  variables.clear();
  equations.clear();
  /* use index from 1; add dummy element 0 */
  equations.append(new OMEquation());
  currentKind = start;
  return true;
}

bool MyHandler::endDocument()
{
  currentVariable.ops.clear(); /* avoid double delete */
  return true;
}

bool MyHandler::characters( const QString & ch )
{
  currentText = ch;
  return true;
}

bool MyHandler::startElement( const QString & namespaceURI, const QString & localName, const QString & qName, const QXmlAttributes & atts)
{
  if (qName == "variable") {
    currentVariable.name = atts.value("name");
    currentVariable.comment = atts.value("comment");
    memset(currentVariable.definedIn,0,sizeof(currentVariable.definedIn));
    for (int i=0; i<equationTypeSize; i++) {
      currentVariable.usedIn[i].clear();
    }
    currentVariable.types.clear();
    currentInfo = OMInfo();
  } else if (qName == "info") {
    currentInfo.file = atts.value("file");
    currentInfo.lineStart = atts.value("lineStart").toLong();
    currentInfo.lineEnd = atts.value("lineEnd").toLong();
    currentInfo.colStart = atts.value("colStart").toLong();
    currentInfo.colEnd = atts.value("colEnd").toLong();
    currentInfo.isValid = true;
  } else if (qName == "equation") {
    currentEquation = new OMEquation();
    currentEquation->index = atts.value("index").toLong();
    currentEquation->parent = atts.value("parent").toLong(); // Returns 0 on failure, which suits us
    currentEquation->kind = currentKind;
    nestedEquations.clear();
    currentInfo = OMInfo();
  } else if (qName == "eq") {
    nestedEquations.append(atts.value("index").toLong());
  } else if (qName == "equations" ||
             qName == "jacobian-equations") {
    currentKind = regular;
  } else if (qName == "initial-equations") {
    currentKind = initial;
  } else if (qName == "parameter-equations") {
    currentKind = parameter;
  } else if (qName == "start-equations") {
    currentKind = start;
  } else if (qName == "defines") {
    currentEquation->defines.append(atts.value("name"));
  } else if (qName == "depends") {
    currentEquation->depends.append(atts.value("name"));
  } else if (qName == "operations") {
    operations.clear();
    hasOperationsEnabled = true;
  } else if (equationTags.contains(qName)) {
    texts.clear();
  } else if (operationTags.contains(qName)) {
    texts.clear();
    if (qName == "scalarize") {
      currentIndex = atts.value("index").toLong();
    }
  }
  return true;
}

bool MyHandler::endElement( const QString & namespaceURI, const QString & localName, const QString & qName)
{
  if (qName == "type") {
    currentVariable.types.append(currentText);
  } else if (operationExpTags.contains(qName) || equationPartTags.contains(qName)) {
    texts.append(currentText.trimmed());
  }
  if (qName == "variable") {
    currentVariable.info = currentInfo;
    currentVariable.ops = operations;
    operations.clear();
    variables[currentVariable.name] = currentVariable;
  } else if (qName == "equation") {
    currentEquation->info = currentInfo;
    currentEquation->ops = operations;
    currentEquation->eqs = nestedEquations;
    operations.clear();
    if (currentEquation->index != equations.size()) {
      printf("failing: %d expect %d\n", currentEquation->index, equations.size()+1);
      return false;
    }
    equations.append(currentEquation);
    foreach (QString def, currentEquation->defines) {
      if (!variables.contains(def)) {
        qDebug() << "Defines " << def << " not found in variables.";
        continue;
      }
      int prev = variables[def].definedIn[currentEquation->kind];
      if (prev) {
        qDebug() << "failing: multiple define of " << def << ": " << prev << " and " << currentEquation->index << " for kind: " << currentEquation->kind;
        return false;
      }
      variables[def].definedIn[currentEquation->kind] = currentEquation->index;
    }
    foreach (QString def, currentEquation->depends) {
      if (variables.contains(def))
        variables[def].usedIn[currentEquation->kind].append(currentEquation->index);
      else
        qDebug() << "Depends " << def << " not found in variables.";
    }
  } else if (equationTags.contains(qName)) {
    currentEquation->text = texts;
    currentEquation->text.prepend(qName);
    texts.clear();
  } else if (qName == "simplify") {
    operations.append(new OMOperationSimplify(texts));
  } else if (qName == "inline") {
    operations.append(new OMOperationInline(texts));
  } else if (qName == "substitution") {
    operations.append(new OMOperationSubstitution(texts));
  } else if (qName == "scalarize") {
    operations.append(new OMOperationScalarize(currentIndex,texts));
  } else if (qName == "solved") {
    operations.append(new OMOperationSolved(texts));
  } else if (qName == "linear-solved") {
    operations.append(new OMOperationLinearSolved(texts));
  } else if (qName == "solve") {
    operations.append(new OMOperationSolve(texts));
  } else if (qName == "derivative") {
    operations.append(new OMOperationDifferentiate(texts));
  } else if (qName == "op-residual") {
    operations.append(new OMOperationResidual(texts));
  } else if (qName == "dummyderivative") {
    operations.append(new OMOperationDummyDerivative(texts));
  } else if (qName == "flattening") {
    operations.append(new OMOperationFlattening(texts));
  }
  return true;
}

bool MyHandler::fatalError(const QXmlParseException & exception)
{
  qWarning() << "Fatal error on line" << exception.lineNumber()
             << ", column" << exception.columnNumber() << ":"
              << exception.message();
  return false;
}

const QSet<QString> MyHandler::operationTags = QSet<QString>() << "simplify" << "substitution" << "inline" << "scalarize" << "solved" << "linear-solved" << "solve" << "derivative" << "op-residual" << "dummyderivative" << "flattening";
const QSet<QString> MyHandler::operationExpTags = QSet<QString>() << "before" << "after" << "lhs" << "rhs" << "exp" << "result" << "with-respect-to" << "chosen" << "candidate" << "original" << "flattened";
const QSet<QString> MyHandler::equationTags = QSet<QString>() << "residual" << "assign" << "statement" << "linear" << "nonlinear" << "mixed" << "when" << "ifequation";
const QSet<QString> MyHandler::equationPartTags = QSet<QString>() << "residual" << "rhs" << "statement" << "row" << "cell";

#if 0

#include <time.h>
static clockid_t omc_clock = CLOCK_MONOTONIC;
struct timespec tick_tp;

void rt_tick() {
  clock_gettime(omc_clock, &tick_tp);
}

double rt_tock() {
  struct timespec tock_tp = {0,0};
  clock_gettime(omc_clock, &tock_tp);
  return (tock_tp.tv_sec - tick_tp.tv_sec) + (tock_tp.tv_nsec - tick_tp.tv_nsec)*1e-9;
}

int test_dump_xml_reader() {
  QFile file("Modelica.Mechanics.MultiBody.Examples.Elementary.DoublePendulum_info.xml");
  rt_tick();
  MyHandler handler(file);
  qDebug() << QString("streaming done in: %1 ms\n").arg(rt_tock() *1e3);
  qDebug() << handler.variables["revolute2.w"].info.toString();
  qDebug() << handler.variables["revolute2.w"].comment;
  qDebug() << handler.equations[1647].info.toString();
  for (int i=0; i<equationTypeSize; i++) {
    const char *var = "boxBody1.body.sphereDiameter";
    if (handler.variables[var].definedIn[i]) {
      qDebug() << var << " defined in (" << OMEquationTypeToString(i) << "): " << handler.variables["boxBody1.body.sphereDiameter"].definedIn[i];
    }
  }
  qDebug() << "text " << handler.equations[1647-1].toString();
  qDebug() << "defines " << handler.equations[1647-1].defines.join(",");
  qDebug() << handler.equations[1].info.toString();
  qDebug() << "eq text: " << handler.equations[1].toString();
  qDebug() << handler.equations[1].defines.join(",");
  qDebug() << "eq1 depends on: " << handler.equations[1].depends;
  qDebug() << "revolute1.frame_b.f[3] operations";
  foreach (OMOperation *op, handler.variables["revolute1.frame_b.f[3]"].ops) {
    qDebug() << op->toString();
  }
  const char *var = "world.nominalLength";
  for (int i=0; i<equationTypeSize; i++) {
    qDebug() << var << " used in (" << OMEquationTypeToString(i) << "): " << handler.variables[var].usedIn[i];
  }
  return 0;
}
#endif
