import json
import sys

try:
    with open('schema.json', 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    defs = data.get('definitions', {})
    if 'bookings' not in defs:
        print("Bookings not found in definitions")
        sys.exit(1)
        
    props = defs['bookings'].get('properties', {})
    for k, v in props.items():
        desc = v.get('description', '')
        if 'fkey' in desc or 'Note:' in desc:
            print(f"{k}: {desc}")
except Exception as e:
    print(e)
