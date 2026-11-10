#!/usr/bin/env python3
"""Write the Open-Meteo answers the tests and review renders use (plugin/tests/fixtures/*.json).

Shapes follow a real answer of 2026-11-08 (forecast_hours=48 starts at the current hour).
"""
import json
import math
import os
from datetime import datetime, timedelta

OUT = os.path.join(os.path.dirname(__file__), '..', 'plugin', 'tests', 'fixtures')


def answer(start, temps, probs, codes, days, cur, unit='celsius'):
    hours = [(start + timedelta(hours=i)).strftime('%Y-%m-%dT%H:%M') for i in range(len(temps))]
    d0 = start.replace(hour=0)
    t_unit = '°F' if unit == 'fahrenheit' else '°C'
    return {
        'latitude': 52.52, 'longitude': 13.419998, 'generationtime_ms': 0.4, 'utc_offset_seconds': 3600,
        'timezone': 'Europe/Berlin', 'timezone_abbreviation': 'GMT+1', 'elevation': 38.0,
        'current_units': {'time': 'iso8601', 'interval': 'seconds', 'temperature_2m': t_unit,
                          'apparent_temperature': t_unit, 'relative_humidity_2m': '%', 'uv_index': '',
                          'wind_speed_10m': 'mp/h' if unit == 'fahrenheit' else 'km/h', 'weather_code': 'wmo code'},
        'current': dict(time=hours[0], interval=900, is_day=1 if 7 <= start.hour <= 16 else 0, **cur),
        'hourly_units': {'time': 'iso8601', 'temperature_2m': t_unit, 'precipitation_probability': '%',
                         'weather_code': 'wmo code'},
        'hourly': {'time': hours, 'temperature_2m': temps, 'precipitation_probability': probs, 'weather_code': codes,
                   'is_day': [1 if 7 <= (start + timedelta(hours=i)).hour <= 16 else 0 for i in range(len(temps))]},
        'daily_units': {'time': 'iso8601', 'weather_code': 'wmo code', 'temperature_2m_max': t_unit,
                        'temperature_2m_min': t_unit, 'precipitation_probability_max': '%', 'uv_index_max': ''},
        'daily': {
            'time': [(d0 + timedelta(days=i)).strftime('%Y-%m-%d') for i in range(len(days))],
            'weather_code': [d[2] for d in days],
            'temperature_2m_max': [d[1] for d in days],
            'temperature_2m_min': [d[0] for d in days],
            'precipitation_probability_max': [d[3] for d in days],
            'uv_index_max': [round(max(0.0, d[1] / 3.5), 1) for d in days],
        },
    }


def mixed():
    # cold morning, sunny noon, rainy evening; starts 06:00
    start = datetime(2026, 11, 8, 6)
    # 06:00 .. 05:00 next day
    base = [1.6, 1.4, 2.3, 4.6, 7.4, 9.8, 11.6, 12.8, 13.1, 12.6, 11.4, 9.9, 8.6, 7.9, 7.4, 7.1,
            6.8, 6.4, 6.0, 5.6, 5.1, 4.6, 4.0, 3.5]
    temps, probs, codes = [], [], []
    for i in range(48):
        h = (6 + i) % 24
        temps.append(round(base[i % 24] + (0.8 if i >= 24 else 0), 1))
        if 17 <= h <= 22:
            probs.append([55, 75, 88, 90, 80, 62][h - 17])
            codes.append([61, 63, 63, 65, 63, 61][h - 17])
        elif 9 <= h <= 14:
            probs.append(3)
            codes.append(0 if h < 13 else 1)
        else:
            probs.append(12)
            codes.append(3 if h > 14 else 2)
    days = [(1.4, 13.1, 63, 90), (2.6, 12.0, 61, 70), (4.0, 9.5, 3, 20), (0.5, 7.2, 71, 60),
            (-2.1, 5.0, 2, 10), (-1.0, 6.4, 1, 5), (3.3, 10.8, 80, 55), (4.1, 11.9, 3, 25),
            (2.0, 9.0, 61, 65), (1.2, 8.1, 2, 15), (0.4, 6.0, 73, 70), (-0.5, 5.5, 1, 5),
            (1.0, 7.7, 3, 20), (2.2, 9.9, 61, 50)]
    cur = {'temperature_2m': 1.6, 'apparent_temperature': -1.9, 'relative_humidity_2m': 91,
           'wind_speed_10m': 11.2, 'weather_code': 2, 'uv_index': 1.8}
    return answer(start, temps, probs, codes, days, cur)


def extreme():
    # thunderstorm day with a -10 to 35 spread across the shown slots; starts 06:00
    start = datetime(2026, 7, 14, 6)
    temps, probs, codes = [], [], []
    for i in range(48):
        h = (6 + i) % 24
        k = i % 24
        t = -10 + 45 * math.sin(math.pi * min(k, 20) / 20) ** 2
        temps.append(round(t, 1))
        if 10 <= k <= 15:
            probs.append(100)
            codes.append(99 if k in (12, 13) else 95)
        elif k < 4 or k > 20:
            probs.append(70)
            codes.append(75)
        else:
            probs.append(40)
            codes.append(80)
    days = [(-10.0, 35.0, 99, 100), (-8.4, 33.2, 95, 100), (-6.0, 30.1, 75, 80), (-9.5, 12.0, 86, 90),
            (2.0, 28.0, 0, 0), (12.0, 34.9, 96, 85), (-3.0, 18.0, 65, 75)] * 2
    cur = {'temperature_2m': -10.0, 'apparent_temperature': -18.4, 'relative_humidity_2m': 100,
           'wind_speed_10m': 88.0, 'weather_code': 95, 'uv_index': 9.4}
    return answer(start, temps, probs, codes, days, cur)


def fahrenheit(a):
    def f(v):
        return None if v is None else round(v * 9 / 5 + 32, 1)
    b = json.loads(json.dumps(a))
    b['hourly']['temperature_2m'] = [f(v) for v in b['hourly']['temperature_2m']]
    b['daily']['temperature_2m_max'] = [f(v) for v in b['daily']['temperature_2m_max']]
    b['daily']['temperature_2m_min'] = [f(v) for v in b['daily']['temperature_2m_min']]
    for k in ('temperature_2m', 'apparent_temperature'):
        b['current'][k] = f(b['current'][k])
    b['current']['wind_speed_10m'] = round(b['current']['wind_speed_10m'] / 1.609, 1)
    for k in ('temperature_2m', 'apparent_temperature'):
        b['current_units'][k] = '°F'
    return b


def main():
    os.makedirs(OUT, exist_ok=True)
    m, x = mixed(), extreme()
    files = {
        'mixed.json': m,
        'extreme.json': x,
        'extreme_f.json': fahrenheit(x),
        'empty.json': {**m, 'hourly': {'time': [], 'temperature_2m': [], 'precipitation_probability': [],
                                       'weather_code': [], 'is_day': []},
                       'daily': {'time': [], 'weather_code': [], 'temperature_2m_max': [], 'temperature_2m_min': [],
                                 'precipitation_probability_max': [], 'uv_index_max': []}},
        'nulls.json': json.loads(json.dumps(m).replace('"temperature_2m": 1.6', '"temperature_2m": null')),
        'error.json': {'error': True, 'reason': 'Latitude must be in range of -90 to 90°. Given: 952.52.'},
    }
    nulls = files['nulls.json']
    nulls['hourly']['temperature_2m'][3:9] = [None] * 6
    nulls['hourly']['precipitation_probability'] = [None] * 48
    for name, data in files.items():
        with open(os.path.join(OUT, name), 'w') as fh:
            json.dump(data, fh, ensure_ascii=False)
            fh.write('\n')
    print('wrote', ', '.join(files))


if __name__ == '__main__':
    main()
