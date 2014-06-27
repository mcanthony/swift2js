//
//  ast.swift
//  swift2js
//
//  Created by Imanol Fernandez @MortimerGoro on 15/06/14.
//  Copyright (c) 2014 swiftjs. All rights reserved.
//

import Foundation

func tabulate(code: String) -> String {
    var result = code.stringByReplacingOccurrencesOfString("\n", withString: "\n\t", options: nil, range: nil);
    if result.hasSuffix("\t") {
        result = result.substringToIndex(result.utf16count - 1);
    }
    result = "\t" + result;
    return result;
}

class ASTContext {
    
    var exportedVars:String[][] = [[]];
    var ctx = 0;
    var generateIDIndex = 0;
    
    func generateID() -> String {
        return "_ref\(generateIDIndex++)";
    }
    
    func exportVar(name:String) {
        if !find(exportedVars[ctx], name) {
            exportedVars[ctx].append(name);
        }
    }
    
    func getExportedVars() ->String? {
        if exportedVars[ctx].count > 0 {
            var result = "";
            result += "var ";
            for variable in exportedVars[ctx] {
                result += variable + ",";
            }
            result = result.substringToIndex(result.utf16count - 1) + ";\n";
            return result;
        }
        
        return nil;
    }
    
    func save() {
        ctx++;
        exportedVars.append([]);
    }
    
    func restore() {
        if ctx > 0 {
            exportedVars.removeLast();
            ctx--;
        }
    }
}

var ctx = ASTContext();


@objc class ASTNode {
    func toJS() -> String {
        return "";
    }
}

@objc class LiteralExpression: ASTNode {
    
    let value: String;
    
    init(_ literal: String) {
        self.value = literal;
    }
    
    override func toJS() -> String {
        return value;
    }
}

@objc class BinaryOperator: ASTNode {
    
    let rightOperand: ASTNode;
    let binaryOperator: String;
    
    init(rightOperand: ASTNode, binaryOperator:String ) {
        self.binaryOperator = binaryOperator;
        self.rightOperand = rightOperand;
    }
    
    override func toJS() -> String {
        if binaryOperator == "." {
            var right = rightOperand.toJS();
            if let index = right.toInt() {
                return "[\(index)]";
            }
            return binaryOperator + right;
        }
        else {
            return " " + binaryOperator + " " + rightOperand.toJS();
        }
    }
}

@objc class AssignmentOperator: ASTNode {
    
    let rightOperand: ASTNode;
    
    init(rightOperand: ASTNode) {
        self.rightOperand = rightOperand;
    }
    
    override func toJS() -> String {
        return " = " + rightOperand.toJS();
    }
}

@objc class TernaryOperator: ASTNode {
    
    let trueOperand: ASTNode;
    let falseOperand: ASTNode;
    
    init(trueOperand: ASTNode, falseOperand: ASTNode) {
        self.trueOperand = trueOperand;
        self.falseOperand = falseOperand;
    }
    
    override func toJS() -> String {
        return " ? " + trueOperand.toJS() + " : " + falseOperand.toJS();
    }
}

@objc class PrefixOperator: ASTNode {
    
    let operand: ASTNode;
    let prefixOperator: String;
    
    init(_ operand: ASTNode, _ prefixOperator:String ) {
        self.operand = operand;
        self.prefixOperator = prefixOperator;
    }
    
    override func toJS() -> String {
        return prefixOperator + operand.toJS();
    }
}

@objc class PostfixOperator: ASTNode {
    
    let operand: ASTNode;
    let postfixOperator: String;
    
    init(_ operand: ASTNode, _ postfixOperator:String ) {
        self.operand = operand;
        self.postfixOperator = postfixOperator;
    }
    
    override func toJS() -> String {
        return operand.toJS() + postfixOperator;
    }
}

@objc class BinaryExpression: ASTNode {
    
    var current:ASTNode?;
    var next:BinaryExpression?;
    
    init(expression:ASTNode?) {
        self.current = expression;
    }
    
    init(expression:ASTNode, next:BinaryExpression?) {
        self.current = expression;
        self.next = next;
    }
    
    //multiple assignmens from a tuple literal. Example: let (a,b) = (1,2)
    func leftAndRightTupleToJS(left: ParenthesizedExpression,_ right: ParenthesizedExpression) -> String {
        var result = "";
        let names = left.toExpressionArray();
        let values = right.toExpressionArray();
        
        for var i = 0; i < names.count; ++i {
            if i >= values.count {
                break;
            }
            result += "\(names[i]) = \(values[i]), ";
        }
        result = result.substringToIndex(result.utf16count - 2); //remove last ", "
        return result;
    }
    
    //multiple assignmens from a expression supposed tu be a tuple. Example: let (a,b) = instance
    func leftTupleAndRightExpressionToJS(left: ParenthesizedExpression,_ right: ASTNode) -> String {
        
        var tupleID = "";
        if let literal = right as? LiteralExpression {
            tupleID = literal.toJS();
        }
        else {
            tupleID = ctx.generateID();
            ctx.exportVar(tupleID + " = " + right.toJS());
        }
        let names = left.toExpressionArray();
        var result = "";
        for var i = 0; i < names.count; ++i {
            result += "\(names[i]) = \(tupleID)[Object.keys(\(tupleID))[\(i)]], ";
        }
        
        result = result.substringToIndex(result.utf16count - 2); //remove last ", "
        
        return result;
    }
    
    
    override func toJS() -> String {
        
        //Check Tuple assignment binary expressions
        if let assignment = next?.current as? AssignmentOperator {
            //check left to right tuple assignment
            let leftTuple = current as? ParenthesizedExpression;
            let rightTuple = assignment.rightOperand as? ParenthesizedExpression;
            if leftTuple && leftTuple!.isList() && rightTuple && rightTuple!.isList() {
                return leftAndRightTupleToJS(leftTuple!, rightTuple!);
            }
            else if leftTuple && leftTuple!.isList() {
                return leftTupleAndRightExpressionToJS(leftTuple!, assignment.rightOperand);
            }
        }
        
        //Generic binary expression
        var result = "";
        if let currentExpression = current {
            result+=currentExpression.toJS();
        }
        if let nextExpression = next {
            result += nextExpression.toJS();
        }
        return result;
    }
}

@objc class NamedExpression: ASTNode {
    
    let name:String;
    let expr:ASTNode;
    
    init(name:String, expr: ASTNode) {
        self.name = name;
        self.expr = expr;
    }
    
    override func toJS() -> String {
        return expr.toJS();
    }
}


@objc class ExpressionList: ASTNode {
    var current:ASTNode?;
    var next:ExpressionList?;
    
    init(expr:ASTNode?, next:ExpressionList?) {
        self.current = expr;
        self.next = next;
    }
    
    
    override func toJS() -> String {
        var result = "";
        if let currentExpression = current {
            result+=currentExpression.toJS();
        }
        if let nextExpression = next {
            result += ", " + nextExpression.toJS();
        }
        return result;
    }
}

@objc class ParenthesizedExpression: ASTNode {
    
    let expression: ASTNode?;
    var allowInlineTuple = true;
    
    
    init(expression: ASTNode?) {
        self.expression = expression;
    }
    
    func toInlineTuple(list: ExpressionList) -> String {
        var result = "{";
        
        var item:ExpressionList? = list;
        var index = 0;
        while let validItem = item {
            
            if let namedExpression = validItem.current as? NamedExpression {
                result += "\(namedExpression.name): \(namedExpression.expr.toJS()), ";
            }
            else if let expression = validItem.current {
                result += "\(index): \(expression.toJS()), ";
            }
            ++index;
            item = validItem.next;
        }
        
        result = result.substringToIndex(result.utf16count - 2); //remove last ', '
        result += "}";
        
        return result;
    }
    
    func isList() ->Bool {
        if let list = expression as? ExpressionList {
            if list.next {
                return true;
            }
        }
        return false;
    }
    
    func toExpressionArray() -> String[] {
        var result = String[]();
        
        var node = expression as? ExpressionList;
        while let item = node {
            result.append(item.current!.toJS());
            node = item.next;
        }
        
        return result;
    }
    
    func toTupleInitializer(variableName: String) -> String {
        let list = expression as ExpressionList;
        var result = variableName + " = ";
        result += variableName + " = " + toInlineTuple(list);
        return result;
    }
    
    override func toJS() -> String {

        if allowInlineTuple {
            if let list = expression as? ExpressionList {
                if list.next {
                    return self.toInlineTuple(list);
                }
            }
        }
        
        if let expr = expression {
            return "(" + expr.toJS() + ")";
        }
        return "()";
    }
}

@objc class FunctionCallExpression: ASTNode {
    let function: ASTNode;
    let parenthesized: ParenthesizedExpression;
    
    init(function: ASTNode, parenthesized: ParenthesizedExpression) {
        self.function = function;
        self.parenthesized = parenthesized;
    }
    
    override func toJS() -> String {
        parenthesized.allowInlineTuple = false;
        return function.toJS() + parenthesized.toJS();
    }
}

@objc class VariableDeclaration: ASTNode {
    let initializer: ExpressionList;
    var exportVariables = true;
    
    init(initializer:ExpressionList) {
        self.initializer = initializer;
    }
    
    func exportVars(expression:BinaryExpression) {
        
        if let tuple = expression.current as? ParenthesizedExpression {
            var names = tuple.toExpressionArray();
            for name in names {
                ctx.exportVar(name);
            }
        }
        else if let expr = expression.current{
            ctx.exportVar(expr.toJS())
        }
    }
    
    override func toJS() -> String {
        if exportVariables {
            var node:ExpressionList? = initializer;
            while let item = node {
                if let expression = item.current as? BinaryExpression {
                    exportVars(expression);
                }
                node = item.next;
            }
            
            var result = initializer.toJS();
            return result;
        }
        else {
            return "var " + initializer.toJS();
        }
    }
}

@objc class ArrayLiteral: ASTNode {
    let items: ASTNode?;
    
    init(items:ASTNode?){
        self.items = items;
    }
    
    override func toJS() -> String {
        var result = "[";
        if let data = items {
            result+=data.toJS();
        }
        result+="]";
        return result;
    }
}

@objc class DictionaryLiteral: ASTNode {
    let pairs: ASTNode?;
    
    init(pairs:ASTNode?){
        self.pairs = pairs;
    }
    
    override func toJS() -> String {
        var result = "{";
        if let data = pairs {
            result += tabulate(data.toJS()) + "\n";
        }
        result+="}";
        return result;
    }
}

@objc class DictionaryItem: ASTNode {
    let key: ASTNode;
    let value: ASTNode;
    
    init(key:ASTNode, value:ASTNode){
        self.key = key;
        self.value = value;
    }
    
    override func toJS() -> String {
        return "\n" + key.toJS() + " : " + value.toJS();
    }
}

@objc class FunctionParameter: ASTNode {
    let inoutVal:Boolean;
    let letVal:Boolean;
    let hashVal:Boolean;
    let external:String;
    let local:String?;
    let defVal:ASTNode?;
    
    init(inoutVal:Boolean, letVal:Boolean, hashVal:Boolean, external:String, local:String?, defVal:ASTNode?) {
        self.inoutVal = inoutVal;
        self.letVal = letVal;
        self.hashVal = hashVal;
        self.external = external;
        self.local = local;
        self.defVal = defVal;
    }
    
    override func toJS() -> String {
        //TODO: default value, inout, etc...
        return local ? local! : external;
    }
    
}

@objc class FunctionDeclaration: ASTNode {
    let name:String;
    let signature:ASTNode?;
    let body:ASTNode?;
    
    init(name:String, signature:ASTNode?, body:ASTNode?) {
        self.name = name;
        self.signature = signature;
        self.body = body;
    }
    
    override func toJS() -> String {
        var result = "function " + name + "(";
        if let parameters = signature {
            result += parameters.toJS();
        }
        result += ") {\n";
        if let statements = body {
            result += tabulate(statements.toJS());
        }
        result += "}";
        return result;
    }
}

@objc class ReturnStatement: ASTNode {
    let returnExpr: ASTNode?;
    
    init(returnExpr: ASTNode?) {
        self.returnExpr = returnExpr;
    }
    
    override func toJS() -> String {
        if let expr = returnExpr {
            return "return " + expr.toJS() + ";";
        }
        
        return "return;"
    }
}

@objc class IfStatement: ASTNode {
    let ifCondition:ASTNode;
    let body:ASTNode?;
    let elseClause:ASTNode?;
    var mustCheckDeclarations = true;
    
    init(ifCondition:ASTNode, body:ASTNode?, elseClause:ASTNode?) {
        self.ifCondition = ifCondition;
        self.body = body;
        self.elseClause = elseClause;
    }
    
    override func toJS() -> String {
        var result = "if (";
        result += ifCondition.toJS();
        result += ") {\n";
        if let statements = body {
            result += tabulate(statements.toJS());
        }
        result += "}";
        if let next = elseClause {
            result += "\nelse "
            if next is IfStatement { //nested if
                 result += next.toJS();
            }
            else {
                result += "{\n" + tabulate(next.toJS()) + "}";
            }
        }
        return result;
        
    }
}

@objc class StatementNode: ASTNode {
    let statement:ASTNode;
    init(statement:ASTNode) {
        self.statement = statement;
    }
    
    override func toJS() -> String {
        return statement.toJS() + ";";
    }
}

@objc class DeclarationStatement: ASTNode {
    let declaration:ASTNode;
    init(declaration:ASTNode) {
        self.declaration = declaration;
    }
    
    override func toJS() -> String {
        if let varDeclaration = declaration as? VariableDeclaration {
            varDeclaration.exportVariables = false;
        }
        return declaration.toJS() + ";";
    }
}

@objc class StatementsNode: ASTNode {
    
    var current:ASTNode?;
    var next:StatementsNode?;
    
    init(current:ASTNode?) {
        self.current = current;
    }
    
    init(current:ASTNode, next:StatementsNode) {
        self.current = current;
        self.next = next;
    }
    
    override func toJS() -> String {
        var result = "";
        if let currentStatement = current {
            ctx.save();
            var tmp = currentStatement.toJS() + "\n";
            if let exported = ctx.getExportedVars() {
                result += exported;
            }
            result += tmp;
            ctx.restore();
        }
        if let nextStatements = next {
            result += nextStatements.toJS();
        }
        return result;
    }
}

