import logging

import azure.functions as func

app = func.FunctionApp()


@app.route(
    route="MyHttpTrigger",
    methods=["GET", "POST"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
@app.service_bus_queue_output(
    arg_name="message",
    queue_name="data",
    connection="ServiceBusConnection",
)
def MyHttpTrigger(
    req: func.HttpRequest,
    message: func.Out[str],
) -> func.HttpResponse:
    logging.info("HTTP trigger received a request to publish a name.")

    name = req.params.get("name")
    if not name:
        try:
            request_body = req.get_json()
        except ValueError:
            request_body = {}
        name = request_body.get("name")

    if not isinstance(name, str) or not name.strip():
        return func.HttpResponse(
            'Provide a non-empty name using ?name=Maria or {"name":"Maria"}.',
            status_code=400,
        )

    name = name.strip()
    message.set(name)
    logging.info("Name was sent to the Service Bus queue.")

    return func.HttpResponse(
        f"Name '{name}' sent to the Service Bus queue.",
        status_code=202,
    )
