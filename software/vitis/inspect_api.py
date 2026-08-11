#!/usr/bin/env python3
import inspect
import vitis

client = vitis.create_client()
try:
    print("client methods:")
    for name in sorted(n for n in dir(client) if not n.startswith("_")):
        print(name)
    print("create_app_component:")
    print(inspect.signature(client.create_app_component))
    print(inspect.getdoc(client.create_app_component))
finally:
    vitis.dispose()
