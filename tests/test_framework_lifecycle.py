from pathlib import Path
import unittest

from lupa import LuaRuntime, lua_type


RESOURCE_ROOT = Path(__file__).resolve().parents[1]
DEPENDENCIES = (
    ("qbx_core", "HasQBX"),
    ("ox_inventory", "HasOxInventory"),
    ("qbx_vehicles", "HasQBXVehicles"),
)


class ResourceHarness:
    def __init__(self, *, server, states=None, load_client_bridge=False):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.states = dict(states or {})
        self.handlers = {}
        self.messages = []
        self.server_events = []
        self.client_events = []
        self.nui_callbacks = {}
        self.clock = 0
        self.threads = []
        self.wait_hook = None

        globals_ = self.lua.globals()
        globals_.Config = self.lua.table()
        globals_.GetResourceState = lambda name: self.states.get(str(name), "missing")
        globals_.IsDuplicityVersion = lambda: server
        globals_.AddEventHandler = self._add_event_handler
        globals_.TriggerEvent = self.emit
        globals_.SendNUIMessage = lambda message: self.messages.append(self._to_python(message))
        globals_.CreateThread = lambda callback: self.threads.append(callback)
        globals_.Wait = self._wait
        globals_.print = lambda *_args: None

        self._execute("shared/bridge.lua")
        if load_client_bridge:
            self._execute("client/bridge.lua")

    @property
    def config(self):
        return self.lua.globals().Config

    def load_client_main(self):
        globals_ = self.lua.globals()
        globals_.json = self.lua.table_from({
            "decode": lambda _value: None,
            "encode": lambda _value: "{}",
        })
        globals_.EsAdminActions = self.lua.table_from({
            "actions": self.lua.table(),
            "tabs": self.lua.table(),
        })
        globals_.GetCurrentResourceName = lambda: "cortex-admin"
        globals_.GetResourceKvpString = lambda _key: None
        globals_.SetResourceKvp = lambda *_args: None
        globals_.PlayerId = lambda: 1
        globals_.PlayerPedId = lambda: 1
        globals_.GetPlayerName = lambda _player: "Admin"
        globals_.GetActivePlayers = lambda: self.lua.table()
        globals_.GetClockHours = lambda: 12
        globals_.GetClockMinutes = lambda: 0
        globals_.IsNextWeatherType = lambda _weather: False
        globals_.GetGameTimer = lambda: 0
        globals_.CreateThread = lambda _callback: None
        globals_.Wait = lambda _milliseconds=0: None
        globals_.RegisterCommand = lambda *_args: None
        globals_.RegisterKeyMapping = lambda *_args: None
        globals_.RegisterNetEvent = self._register_net_event
        globals_.TriggerServerEvent = self._capture_server_event

        # Populate defaults/KVP keys without replacing the detected framework flags.
        self._execute("shared/config.lua")
        self._execute("client/main.lua")

    def load_client_nui(self):
        self.lua.globals().RegisterNUICallback = self._register_nui_callback
        self._execute("client/nui.lua")

    def load_server_main(self, bridge):
        globals_ = self.lua.globals()
        globals_.EsAdminActions = self.lua.table_from({"actions": self.lua.table()})
        globals_.EsAdminServer = self.lua.table()
        globals_.EsAdminBridge = bridge
        globals_.RegisterNetEvent = self._register_net_event
        globals_.TriggerClientEvent = self._capture_client_event
        globals_.GetGameTimer = self._next_clock
        globals_.IsPlayerAceAllowed = lambda *_args: True
        globals_.GetPlayerName = lambda player: "Admin" if player == 1 else None
        globals_.GetPlayerIdentifiers = lambda player: self.lua.table_from([f"license:{player}"])
        globals_.GetPlayerRoutingBucket = lambda _player: 0
        globals_.GetPlayerPed = lambda player: player
        globals_.GetEntityCoords = lambda _ped: self.lua.table_from({"x": 0.0, "y": 0.0, "z": 0.0})
        globals_.GetCurrentResourceName = lambda: "cortex-admin"
        globals_.GetResourcePath = lambda _resource=None: str(RESOURCE_ROOT)
        globals_.json = self.lua.table_from({
            "decode": lambda _value: self.lua.table(),
            "encode": lambda _value: "{}",
        })
        if globals_.exports is None:
            globals_.exports = self.lua.table()

        self._execute("shared/config.lua")
        self._execute("shared/wardrobe_share.lua")
        self._execute("server/main.lua")

    def _register_net_event(self, name, callback=None):
        if callback is not None:
            self._add_event_handler(name, callback)

    def _register_nui_callback(self, name, callback):
        self.nui_callbacks[str(name)] = callback

    def _capture_server_event(self, name, *args):
        self.server_events.append({
            "name": str(name),
            "args": tuple(self._to_python(arg) for arg in args),
        })

    def _capture_client_event(self, name, target, *args):
        self.client_events.append({
            "name": str(name),
            "target": target,
            "args": tuple(self._to_python(arg) for arg in args),
        })

    def _next_clock(self):
        self.clock += 10001
        return self.clock

    def _wait(self, _milliseconds=0):
        if self.wait_hook is not None:
            hook, self.wait_hook = self.wait_hook, None
            hook()

    def invoke_nui(self, name, data=None):
        replies = []
        callback = self.nui_callbacks[str(name)]
        callback(self.lua.table_from(data or {}), lambda reply: replies.append(self._to_python(reply)))
        return replies

    def invoke_net(self, name, source, *args):
        self.lua.globals().source = source
        try:
            self.emit(name, *args)
        finally:
            self.lua.globals().source = None

    def _execute(self, relative_path):
        source = (RESOURCE_ROOT / relative_path).read_text(encoding="utf-8")
        return self.lua.execute(source)

    def _add_event_handler(self, name, callback):
        self.handlers.setdefault(str(name), []).append(callback)

    def emit(self, name, *args):
        for callback in tuple(self.handlers.get(str(name), ())):
            callback(*args)

    def run_threads(self):
        pending, self.threads = self.threads, []
        for callback in pending:
            callback()

    def _to_python(self, value):
        if lua_type(value) != "table":
            return value
        return {self._to_python(key): self._to_python(item) for key, item in value.items()}


class FrameworkLifecycleTests(unittest.TestCase):
    def all_started(self):
        return {resource: "started" for resource, _flag in DEPENDENCIES}

    def test_initial_detection_does_not_advertise_starting_resources(self):
        harness = ResourceHarness(
            server=True,
            states={resource: "starting" for resource, _flag in DEPENDENCIES},
        )

        self.assertEqual("standalone", harness.config.Framework)
        self.assertEqual("none", harness.config.Inventory)
        for _resource, flag in DEPENDENCIES:
            self.assertFalse(harness.config[flag])

    def test_server_lifecycle_re_detects_each_dependency_start_stop_start(self):
        for resource, flag in DEPENDENCIES:
            with self.subTest(resource=resource):
                harness = ResourceHarness(server=True, states=self.all_started())
                self.assertTrue(harness.config[flag])

                # Stop callbacks can arrive while GetResourceState still reports the
                # previous value. The stopped resource must be forced unavailable.
                harness.emit("onResourceStop", resource)
                self.assertFalse(harness.config[flag])

                harness.states[resource] = "starting"
                harness.emit("onResourceStart", resource)
                self.assertFalse(harness.config[flag])

                # Cfx can deliver the start callback before GetResourceState flips
                # from "starting" to "started". The deferred lifecycle check must
                # observe readiness without requiring a second start event.
                harness.states[resource] = "started"
                harness.run_threads()
                self.assertTrue(harness.config[flag])

    def test_stop_cancels_a_start_check_that_is_waiting(self):
        harness = ResourceHarness(server=True, states=self.all_started())

        harness.emit("onResourceStop", "qbx_core")
        harness.states["qbx_core"] = "starting"
        harness.emit("onResourceStart", "qbx_core")
        harness.states["qbx_core"] = "started"
        harness.wait_hook = lambda: harness.emit("onResourceStop", "qbx_core")

        harness.run_threads()

        self.assertFalse(harness.config.HasQBX)

    def test_client_lifecycle_uses_client_events_and_refreshes_nui_snapshot(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )

        harness.emit("onClientResourceStop", "ox_inventory")

        self.assertFalse(harness.config.HasOxInventory)
        self.assertTrue(harness.messages)
        update = harness.messages[-1]
        self.assertEqual("cortex-admin:setState", update["action"])
        self.assertFalse(update["data"]["frameworkInfo"]["hasInventory"])
        self.assertEqual({}, update["data"]["inventoryItems"])

        message_count = len(harness.messages)
        harness.states["ox_inventory"] = "starting"
        harness.emit("onClientResourceStart", "ox_inventory")
        self.assertFalse(harness.config.HasOxInventory)
        self.assertEqual(message_count, len(harness.messages))

        harness.states["ox_inventory"] = "started"
        harness.run_threads()
        self.assertTrue(harness.config.HasOxInventory)
        self.assertTrue(harness.messages[-1]["data"]["frameworkInfo"]["hasInventory"])

    def test_delayed_inventory_response_from_before_restart_is_ignored(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )
        harness.load_client_main()
        harness.load_client_nui()

        harness.invoke_nui("cortex-admin:requestItems")
        request = harness.server_events[-1]
        self.assertEqual("cortex-admin:server:getItems", request["name"])
        old_generation = request["args"][0]["generation"]

        harness.emit("onClientResourceStop", "ox_inventory")
        harness.states["ox_inventory"] = "started"
        harness.emit("onClientResourceStart", "ox_inventory")

        harness.messages.clear()
        stale_items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "old_item", "label": "Old Item", "weight": 1})
        })
        harness.emit("cortex-admin:client:setItems", stale_items, old_generation)
        self.assertEqual([], harness.messages)

        harness.invoke_nui("cortex-admin:requestItems")
        current_generation = harness.server_events[-1]["args"][0]["generation"]
        self.assertNotEqual(old_generation, current_generation)

        current_items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "water", "label": "Water", "weight": 1})
        })
        harness.emit("cortex-admin:client:setItems", current_items, current_generation)
        self.assertEqual("cortex-admin:setState", harness.messages[-1]["action"])
        self.assertEqual("water", harness.messages[-1]["data"]["inventoryItems"][1]["name"])

    def test_delayed_garage_response_from_before_restart_is_ignored(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )
        harness.load_client_main()
        harness.load_client_nui()

        harness.invoke_nui("cortex-admin:requestGarage")
        request = harness.server_events[-1]
        self.assertEqual("cortex-admin:server:getPlayerGarage", request["name"])
        old_generation = request["args"][0]["generation"]

        harness.emit("onClientResourceStop", "qbx_vehicles")
        harness.states["qbx_vehicles"] = "started"
        harness.emit("onClientResourceStart", "qbx_vehicles")

        harness.messages.clear()
        stale_vehicles = harness.lua.table_from({
            1: harness.lua.table_from({"id": 1, "model": "oldcar"})
        })
        harness.emit("cortex-admin:client:setGarageVehicles", stale_vehicles, old_generation)
        self.assertEqual([], harness.messages)

        harness.invoke_nui("cortex-admin:requestGarage")
        current_generation = harness.server_events[-1]["args"][0]["generation"]
        self.assertNotEqual(old_generation, current_generation)

        current_vehicles = harness.lua.table_from({
            1: harness.lua.table_from({"id": 2, "model": "sultan"})
        })
        harness.emit("cortex-admin:client:setGarageVehicles", current_vehicles, current_generation)
        self.assertEqual("cortex-admin:setState", harness.messages[-1]["action"])
        self.assertEqual("sultan", harness.messages[-1]["data"]["garageVehicles"][1]["model"])

    def test_qbx_stop_disables_dependent_ui_capabilities(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )

        harness.emit("onClientResourceStop", "qbx_core")

        state_updates = [message for message in harness.messages if message["action"] == "cortex-admin:setState"]
        tab_updates = [message for message in harness.messages if message["action"] == "cortex-admin:setTab"]
        info = state_updates[-1]["data"]["frameworkInfo"]
        self.assertFalse(info["hasQBX"])
        self.assertFalse(info["hasInventory"])
        self.assertFalse(info["hasGarage"])
        self.assertEqual({}, state_updates[-1]["data"]["inventoryItems"])
        self.assertEqual({}, state_updates[-1]["data"]["garageVehicles"])
        self.assertEqual("all", tab_updates[-1]["data"]["tab"])

    def test_qbx_stop_rejects_current_generation_inventory_and_garage_responses(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )
        harness.load_client_main()
        harness.load_client_nui()

        harness.emit("onClientResourceStop", "qbx_core")
        generation = harness.lua.globals().EsAdminBridge.getFrameworkGeneration()
        harness.messages.clear()

        items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "water", "label": "Water", "weight": 1})
        })
        vehicles = harness.lua.table_from({
            1: harness.lua.table_from({"id": 2, "model": "sultan"})
        })
        harness.emit("cortex-admin:client:setItems", items, generation)
        harness.emit("cortex-admin:client:setGarageVehicles", vehicles, generation)

        self.assertEqual([], harness.messages)

    def test_each_menu_state_build_reads_the_live_framework_snapshot(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )
        harness.load_client_main()

        harness.messages.clear()
        harness.lua.globals().EsAdmin.sendUiState()
        self.assertTrue(harness.messages[-1]["data"]["frameworkInfo"]["hasQBX"])

        harness.emit("onClientResourceStop", "qbx_core")
        harness.messages.clear()
        harness.lua.globals().EsAdmin.sendUiState()

        info = harness.messages[-1]["data"]["frameworkInfo"]
        self.assertFalse(info["hasQBX"])
        self.assertFalse(info["hasInventory"])
        self.assertFalse(info["hasGarage"])

    def test_server_bridge_clears_dependency_caches_across_restart(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        exports, inventory_calls = harness.lua.execute(
            """
            local calls = 0
            local inventory = {}
            function inventory:Items()
                calls = calls + 1
                return { water = { label = 'Water', weight = 1 } }
            end
            return { ox_inventory = inventory }, function() return calls end
            """
        )
        harness.lua.globals().exports = exports
        harness._execute("server/bridge.lua")

        harness.lua.globals().EsAdminBridge.getAllItems()
        harness.lua.globals().EsAdminBridge.getAllItems()
        self.assertEqual(1, inventory_calls())

        harness.emit("onResourceStop", "ox_inventory")
        harness.states["ox_inventory"] = "started"
        harness.emit("onResourceStart", "ox_inventory")
        harness.lua.globals().EsAdminBridge.getAllItems()

        self.assertEqual(2, inventory_calls())

    def test_server_bridge_does_not_cache_export_result_across_restart(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        calls = 0
        stale_items = harness.lua.table_from({
            "old_item": harness.lua.table_from({"label": "Old Item", "weight": 1})
        })
        fresh_items = harness.lua.table_from({
            "water": harness.lua.table_from({"label": "Water", "weight": 1})
        })

        def get_items(*_args):
            nonlocal calls
            calls += 1
            if calls == 1:
                harness.emit("onResourceStop", "ox_inventory")
                harness.emit("onResourceStart", "ox_inventory")
                return stale_items
            return fresh_items

        inventory = harness.lua.table_from({"Items": get_items})
        harness.lua.globals().exports = harness.lua.table_from({"ox_inventory": inventory})
        harness._execute("server/bridge.lua")

        first = harness.lua.globals().EsAdminBridge.getAllItems()
        second = harness.lua.globals().EsAdminBridge.getAllItems()

        self.assertEqual(0, len(first))
        self.assertEqual(2, calls)
        self.assertEqual("water", second[1]["name"])

    def test_server_inventory_response_echoes_client_generation(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "water", "label": "Water", "weight": 1})
        })
        bridge = harness.lua.table_from({"getAllItems": lambda: items})
        harness.load_server_main(bridge)

        harness.invoke_net(
            "cortex-admin:server:getItems",
            1,
            harness.lua.table_from({"generation": 17}),
        )

        response = next(
            event for event in harness.client_events
            if event["name"] == "cortex-admin:client:setItems"
        )
        self.assertEqual(1, response["target"])
        self.assertEqual(17, response["args"][1])

    def test_server_drops_inventory_response_if_dependency_stops_during_fetch(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "old_item", "label": "Old Item", "weight": 1})
        })

        def stop_during_fetch():
            harness.emit("onResourceStop", "ox_inventory")
            return items

        bridge = harness.lua.table_from({"getAllItems": stop_during_fetch})
        harness.load_server_main(bridge)

        harness.invoke_net(
            "cortex-admin:server:getItems",
            1,
            harness.lua.table_from({"generation": 21}),
        )

        responses = [
            event for event in harness.client_events
            if event["name"] == "cortex-admin:client:setItems"
        ]
        self.assertEqual([], responses)

    def test_server_drops_inventory_response_if_dependency_restarts_during_fetch(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        items = harness.lua.table_from({
            1: harness.lua.table_from({"name": "old_item", "label": "Old Item", "weight": 1})
        })

        def restart_during_fetch():
            harness.emit("onResourceStop", "ox_inventory")
            harness.states["ox_inventory"] = "started"
            harness.emit("onResourceStart", "ox_inventory")
            return items

        bridge = harness.lua.table_from({"getAllItems": restart_during_fetch})
        harness.load_server_main(bridge)

        harness.invoke_net(
            "cortex-admin:server:getItems",
            1,
            harness.lua.table_from({"generation": 22}),
        )

        responses = [
            event for event in harness.client_events
            if event["name"] == "cortex-admin:client:setItems"
        ]
        self.assertEqual([], responses)

    def test_server_garage_response_echoes_client_generation(self):
        harness = ResourceHarness(server=True, states=self.all_started())
        vehicles = harness.lua.table_from({
            1: harness.lua.table_from({"id": 2, "model": "sultan"})
        })
        bridge = harness.lua.table_from({
            "getPlayerCitizenId": lambda _source: "citizen-1",
            "getPlayerVehicles": lambda _citizen_id: vehicles,
        })
        harness.load_server_main(bridge)

        harness.invoke_net(
            "cortex-admin:server:getPlayerGarage",
            1,
            harness.lua.table_from({"generation": 33}),
        )

        response = next(
            event for event in harness.client_events
            if event["name"] == "cortex-admin:client:setGarageVehicles"
        )
        self.assertEqual(1, response["target"])
        self.assertEqual(33, response["args"][1])

    def test_server_drops_garage_response_if_dependency_stops_during_fetch(self):
        for stopped_resource in ("qbx_core", "qbx_vehicles"):
            with self.subTest(stopped_resource=stopped_resource):
                harness = ResourceHarness(server=True, states=self.all_started())
                vehicles = harness.lua.table_from({
                    1: harness.lua.table_from({"id": 1, "model": "oldcar"})
                })

                def get_citizen_id(_source):
                    if stopped_resource == "qbx_core":
                        harness.emit("onResourceStop", stopped_resource)
                    return "citizen-1"

                def get_vehicles(_citizen_id):
                    if stopped_resource == "qbx_vehicles":
                        harness.emit("onResourceStop", stopped_resource)
                    return vehicles

                bridge = harness.lua.table_from({
                    "getPlayerCitizenId": get_citizen_id,
                    "getPlayerVehicles": get_vehicles,
                })
                harness.load_server_main(bridge)

                harness.invoke_net(
                    "cortex-admin:server:getPlayerGarage",
                    1,
                    harness.lua.table_from({"generation": 34}),
                )

                responses = [
                    event for event in harness.client_events
                    if event["name"] == "cortex-admin:client:setGarageVehicles"
                ]
                self.assertEqual([], responses)

    def test_server_drops_garage_response_if_dependency_restarts_during_fetch(self):
        for restarted_resource in ("qbx_core", "qbx_vehicles"):
            with self.subTest(restarted_resource=restarted_resource):
                harness = ResourceHarness(server=True, states=self.all_started())
                vehicles = harness.lua.table_from({
                    1: harness.lua.table_from({"id": 1, "model": "oldcar"})
                })

                def restart_dependency():
                    harness.emit("onResourceStop", restarted_resource)
                    harness.states[restarted_resource] = "started"
                    harness.emit("onResourceStart", restarted_resource)

                def get_citizen_id(_source):
                    if restarted_resource == "qbx_core":
                        restart_dependency()
                    return "citizen-1"

                def get_vehicles(_citizen_id):
                    if restarted_resource == "qbx_vehicles":
                        restart_dependency()
                    return vehicles

                bridge = harness.lua.table_from({
                    "getPlayerCitizenId": get_citizen_id,
                    "getPlayerVehicles": get_vehicles,
                })
                harness.load_server_main(bridge)

                harness.invoke_net(
                    "cortex-admin:server:getPlayerGarage",
                    1,
                    harness.lua.table_from({"generation": 35}),
                )

                responses = [
                    event for event in harness.client_events
                    if event["name"] == "cortex-admin:client:setGarageVehicles"
                ]
                self.assertEqual([], responses)

    def test_irrelevant_resource_events_do_not_change_or_broadcast_capabilities(self):
        harness = ResourceHarness(
            server=False,
            states=self.all_started(),
            load_client_bridge=True,
        )

        harness.emit("onClientResourceStop", "unrelated-resource")

        self.assertTrue(harness.config.HasQBX)
        self.assertTrue(harness.config.HasOxInventory)
        self.assertTrue(harness.config.HasQBXVehicles)
        self.assertEqual([], harness.messages)


if __name__ == "__main__":
    unittest.main()
