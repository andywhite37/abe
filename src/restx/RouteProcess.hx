package restx;

import express.Next;
import express.Request;
import express.Response;
import js.Error;
import restx.core.ArgumentProcessor;

class RouteProcess<TRoute : IRoute, TArgs : {}> {
  var instance : IRoute;
  var argumentProcessor : ArgumentProcessor<TArgs>;
  var arguments : TArgs;
  public function new(instance : IRoute, argumentProcessor : ArgumentProcessor<TArgs>) {
    this.instance = instance;
    this.argumentProcessor = argumentProcessor;
  }

  public function run(req : Request, res : Response, next : Next) {
    switch argumentProcessor.processArguments(req) {
      case Ok(args):
        instance.request = req;
        instance.response = res;
        instance.next = next;
        arguments = args;
        execute();
      case Required(msg), InvalidType(msg):
        // TODO add proper status code
        (next : Error -> Void)(new Error(msg));
    }
  }

  function execute()
    throw 'RouteProcess.execute() must be overwritten';
}