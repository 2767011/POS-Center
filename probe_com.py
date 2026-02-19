# -*- coding: utf-8 -*-
"""Probe script - shows all properties and methods of SrvFRLib.SrvFR COM object"""
import sys
import win32com.client

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

COM_PROG_IDS = ["AddIn.DrvFR", "SrvFRLib.SrvFR"]

drv = None
used_progid = None
for prog_id in COM_PROG_IDS:
    try:
        drv = win32com.client.Dispatch(prog_id)
        used_progid = prog_id
        print(f"COM object created: {prog_id}")
        break
    except Exception as e:
        print(f"  {prog_id}: {e}")

if not drv:
    print("ERROR: No COM driver found")
    sys.exit(1)

# Try EnsureDispatch for early binding (typelib)
try:
    drv2 = win32com.client.gencache.EnsureDispatch(used_progid)
    print(f"Early binding (EnsureDispatch) OK for {used_progid}")
    drv = drv2
except Exception as e:
    print(f"Early binding failed: {e}")
    print("Using late binding (Dispatch)")

# List all members
print("\n=== Properties ===")
props = []
methods = []

# Try to get type info
try:
    import win32com.client.dynamic
    ti = drv._oleobj_.GetTypeInfo()
    ta = ti.GetTypeAttr()
    for i in range(ta.cFuncs):
        fd = ti.GetFuncDesc(i)
        names = ti.GetNames(fd.memid)
        name = names[0] if names else f"func_{i}"
        invkind = fd.invkind
        # invkind: 1=METHOD, 2=PROPERTYGET, 4=PROPERTYPUT, 8=PROPERTYPUTREF
        if invkind == 1:
            methods.append(name)
        elif invkind in (2, 4, 8):
            if name not in props:
                props.append(name)
    
    props.sort()
    methods.sort()
    
    for p in props:
        try:
            val = getattr(drv, p, "???")
            print(f"  {p} = {val}")
        except Exception:
            print(f"  {p} = <error reading>")
    
    print(f"\n=== Methods ({len(methods)}) ===")
    for m in methods:
        print(f"  {m}()")

except Exception as e:
    print(f"Cannot enumerate type info: {e}")
    print("Trying common properties manually...")
    
    test_props = [
        "Password", "SysAdminPassword", "ConnectionType", "IPAddress", 
        "TCPPort", "UseIPAddress", "Timeout", "ComNumber", "BaudRate",
        "ResultCode", "ResultCodeDescription", "ECRMode", "ECRModeDescription",
        "TableNumber", "RowNumber", "FieldNumber", "ValueOfFieldInteger",
        "ValueOfFieldString", "UnitType"
    ]
    for p in test_props:
        try:
            val = getattr(drv, p)
            print(f"  {p} = {val} (readable)")
        except AttributeError:
            print(f"  {p} = NOT FOUND")
        except Exception as ex:
            print(f"  {p} = ERROR: {ex}")
    
    test_methods = [
        "Connect", "Disconnect", "GetShortECRStatus", "GetECRStatus",
        "ReadTable", "WriteTable", "RepeatDocument", "WaitForPrinting",
        "FNGetStatus", "FNOperation", "FNCloseCheckEx", "OpenCheck",
        "GetDeviceMetrics", "FNGetSerial"
    ]
    print("\n=== Methods (manual check) ===")
    for m in test_methods:
        try:
            func = getattr(drv, m)
            print(f"  {m}() = EXISTS")
        except AttributeError:
            print(f"  {m}() = NOT FOUND")
        except Exception as ex:
            print(f"  {m}() = ERROR: {ex}")

print("\nDone.")
input("Press Enter to exit...")
