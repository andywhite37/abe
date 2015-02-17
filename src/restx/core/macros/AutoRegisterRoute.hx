package restx.core.macros;

import haxe.macro.Type;
import haxe.macro.Context;
import haxe.macro.Expr;
using haxe.macro.TypeTools;
import restx.core.macros.Macros.*;

class AutoRegisterRoute {
  public static function register(router : Expr, instance : Expr) : Expr {
    // get the type
    var type = getClassType(instance);

    // iterate on all the fields and filter the functions that have @:path
    var fields = filterControllerMethods(type.fields.get());

    var definitions = fields.map(function(field) {
        var metas   = field.meta.get(),
            meta    = findMeta(metas, ":path"),
            path    = getMetaAsString(meta, 0),
            args    = getArguments(field);
        return {
          name : field.name,
          path : path,
          arguments : args
        };
      });

    if(definitions.length == 0) {
      Context.error("There are no controller methods defined in this class", Context.currentPos());
    }

    var exprs = definitions.map(function(definition) {
        // for each iterate on all the HTTP methods (at least Get)

        // create a class type for each controller function
        var processName = [type.name, definition.name, "RouteProcess"].join("_"),
            fullName = type.pack.concat([processName]).join("."),
            fields = createProcessFields(definition.name, definition.arguments),
            exprs  = [];

        exprs.push(Context.parse('var filters = new restx.core.ArgumentsFilter()',
                  Context.currentPos()));
        var args = definition.arguments.map(function(arg) {
            var sources = arg.sources.map(function(s) return '"$s"').join(", ");
            return '{
              name     : "${arg.name}",
              optional : ${arg.optional},
              type     : "${arg.type}",
              sources : [$sources]
            }';
          }).join(", ");
        exprs.push(Context.parse('var processor = new restx.core.ArgumentProcessor(filters, [${args}])',
                  Context.currentPos()));
        exprs.push(Context.parse('var process = new $fullName(instance, processor)',
                  Context.currentPos()));

        var path = definition.path,
            method = "get"; // TODO
        exprs.push(macro router.registerMethod($v{path}, $v{method}, cast process));

        var params = definition.arguments.map(function(arg) : Field return {
              pos : Context.currentPos(),
              name : arg.name,
              kind : FVar(Context.follow(Context.getType(arg.type)).toComplexType())
            });

        Context.defineType({
            pos  : Context.currentPos(),
            pack : type.pack,
            name : processName,
            kind : TDClass({
                pack : ["restx"],
                name : "RouteProcess",
                params : [
                  TPType(TPath({
                    sub : type.name,
                    pack : type.pack,
                    name : type.module.split(".").pop()
                  })),
                  TPType(TAnonymous(params))]
              }, [], false),
            fields : fields,
          });

        // pass additional filters
        return macro $b{exprs};
      });

    // registerMethod(path, method, router)
    return macro (function(instance, router) {
      $b{exprs}
    })($instance, $router);
  }

  static function getClassType(expr : Expr) return switch Context.follow(Context.typeof(expr)) {
    case TInst(t, _) if(classImplementsInterface(t.get(), "restx.IRoute")): t.get();
    case _: Context.error('expression in Router.register must be an instance of an IRoute', Context.currentPos());
  }

  static function classImplementsInterface(cls : ClassType, test : String) {
    for(interf in cls.interfaces) {
      if(test == interf.t.toString())
        return true;
    }
    return false;
  }

  static function filterControllerMethods(fields : Array<ClassField>) {
    var results = [];
    for(field in fields) {
      for(meta in field.meta.get()) {
        if(meta.name != ":path")
          continue;
        results.push(field);
        break;
      }
    }
    return results;
  }

  static function createProcessFields(name : String, args : Array<ArgumentRequirement>) {
    var arguments = args.map(function(arg) {
            return 'arguments.${arg.name}';
          }).join(", "),
        execute = 'instance.$name($arguments)';
    return [createFunctionField("execute", [AOverride], Context.parse(execute, Context.currentPos()))];
  }

  static function getArguments(field : ClassField) : Array<ArgumentRequirement> {
    return switch Context.follow(field.type) {
      case TFun(args, _):
        args.map(function(arg) {
          return {
              name : arg.name,
              optional : arg.opt,
              type : arg.t.toString(),
              sources : ["get"]
          };
        });
      case _: [];
    };
  }
}