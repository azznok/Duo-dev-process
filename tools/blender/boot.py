# Starts the Blender MCP server (blender_mcp add-on) when Blender launches.
#   blender.exe --python tools/blender/boot.py      (bin/harness/lib/common.ps1 : Ensure-Blender)
# After a PC reboot the add-on no longer enabled itself and every relaunch stacked
# up a silent Blender: so we enable the add-on and start the server EXPLICITLY.
# Port: HARNESS_BLENDER_PORT or BLENDER_PORT from the environment if set (config BLENDER_PORT),
# otherwise the add-on's default; it must match the port the harness probes.
import os

import bpy

try:
    bpy.ops.preferences.addon_enable(module='blender_mcp')
except Exception as e:
    print('addon_enable:', e)
port = os.environ.get('HARNESS_BLENDER_PORT') or os.environ.get('BLENDER_PORT')
if port:
    try:
        bpy.context.scene.blendermcp_port = int(port)
    except Exception as e:   # older add-on without the property: keep its default
        print('blendermcp_port:', e)
try:
    bpy.ops.blendermcp.start_server()
    print('MCP_START_OK')
except Exception as e:
    print('start_server:', e)
