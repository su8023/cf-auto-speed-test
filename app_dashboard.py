#!/usr/bin/env python3
"""
CF Auto Speed Test - Web Dashboard
Flask-based dashboard to display speed test results
Binds to 0.0.0.0:5001
"""

import os
import csv
import glob
from datetime import datetime
from flask import Flask, render_template_string, jsonify

app = Flask(__name__)
LOG_DIR = "log"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CF Speed Test Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #eee; min-height: 100vh; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        h1 { text-align: center; color: #f39c12; margin-bottom: 30px; padding: 20px; background: #16213e; border-radius: 10px; }
        .section { background: #16213e; border-radius: 10px; padding: 20px; margin-bottom: 20px; }
        .section h2 { color: #3498db; margin-bottom: 15px; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #2c3e50; }
        th { background: #0f3460; color: #f39c12; }
        tr:hover { background: #1f4068; }
        .speed-high { color: #2ecc71; }
        .speed-medium { color: #f39c12; }
        .speed-low { color: #e74c3c; }
        .history-list { list-style: none; }
        .history-item { padding: 10px; margin: 5px 0; background: #0f3460; border-radius: 5px; display: flex; justify-content: space-between; }
        .history-item span:first-child { color: #3498db; }
        .nav { display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        .nav a { padding: 10px 20px; background: #0f3460; color: #fff; text-decoration: none; border-radius: 5px; transition: background 0.3s; }
        .nav a:hover, .nav a.active { background: #3498db; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .stat-card { background: #0f3460; padding: 20px; border-radius: 10px; text-align: center; }
        .stat-card .value { font-size: 2em; color: #f39c12; }
        .stat-card .label { color: #888; margin-top: 5px; }
        .refresh-btn { padding: 10px 20px; background: #27ae60; color: #fff; border: none; border-radius: 5px; cursor: pointer; margin-bottom: 15px; }
        .refresh-btn:hover { background: #2ecc71; }
        .no-data { text-align: center; color: #888; padding: 40px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>☁️ Cloudflare Speed Test Dashboard</h1>
        
        <div class="nav">
            <a href="/" class="active">📊 Overview</a>
            <a href="/history">📜 History</a>
            <button class="refresh-btn" onclick="location.reload()">🔄 Refresh</button>
        </div>

        <div class="stats">
            <div class="stat-card">
                <div class="value">{{ total_tests }}</div>
                <div class="label">Total Tests</div>
            </div>
            <div class="stat-card">
                <div class="value">{{ total_ips }}</div>
                <div class="label">IPs Tested</div>
            </div>
            <div class="stat-card">
                <div class="value">{{ regions }}</div>
                <div class="label">Regions</div>
            </div>
            <div class="stat-card">
                <div class="value">{{ last_update }}</div>
                <div class="label">Last Update</div>
            </div>
        </div>

        <div class="section">
            <h2>🏆 Best IPs by Region</h2>
            {% if best_ips %}
            <table>
                <tr>
                    <th>Region</th>
                    <th>Port</th>
                    <th>IP</th>
                    <th>Speed (Mbps)</th>
                    <th>Latency (ms)</th>
                    <th>Loss (%)</th>
                </tr>
                {% for row in best_ips %}
                <tr>
                    <td>{{ row.region }}</td>
                    <td>{{ row.port }}</td>
                    <td>{{ row.ip }}</td>
                    <td class="{{ row.speed_class }}">{{ row.speed }} Mbps</td>
                    <td>{{ row.latency }} ms</td>
                    <td>{{ row.loss }}%</td>
                </tr>
                {% endfor %}
            </table>
            {% else %}
            <div class="no-data">No speed test data available. Run a speed test first.</div>
            {% endif %}
        </div>

        <div class="section">
            <h2>📋 All Recent Results</h2>
            {% if all_results %}
            <table>
                <tr>
                    <th>Time</th>
                    <th>Region</th>
                    <th>Port</th>
                    <th>IP</th>
                    <th>Speed (Mbps)</th>
                    <th>Latency (ms)</th>
                    <th>Loss (%)</th>
                </tr>
                {% for row in all_results[:50] %}
                <tr>
                    <td>{{ row.time }}</td>
                    <td>{{ row.region }}</td>
                    <td>{{ row.port }}</td>
                    <td>{{ row.ip }}</td>
                    <td class="{{ row.speed_class }}">{{ row.speed }} Mbps</td>
                    <td>{{ row.latency }} ms</td>
                    <td>{{ row.loss }}%</td>
                </tr>
                {% endfor %}
            </table>
            {% else %}
            <div class="no-data">No results found in log directory.</div>
            {% endif %}
        </div>
    </div>
</body>
</html>
"""

HISTORY_TEMPLATE = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>History - CF Speed Test Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #eee; min-height: 100vh; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        h1 { text-align: center; color: #f39c12; margin-bottom: 30px; padding: 20px; background: #16213e; border-radius: 10px; }
        .section { background: #16213e; border-radius: 10px; padding: 20px; margin-bottom: 20px; }
        .section h2 { color: #3498db; margin-bottom: 15px; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .nav { display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        .nav a { padding: 10px 20px; background: #0f3460; color: #fff; text-decoration: none; border-radius: 5px; transition: background 0.3s; }
        .nav a:hover, .nav a.active { background: #3498db; }
        .history-list { list-style: none; }
        .history-item { padding: 15px; margin: 10px 0; background: #0f3460; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; }
        .history-item .file { color: #3498db; font-weight: bold; }
        .history-item .meta { color: #888; }
        .history-item .size { color: #f39c12; }
        .back-btn { padding: 10px 20px; background: #27ae60; color: #fff; text-decoration: none; border-radius: 5px; }
        .back-btn:hover { background: #2ecc71; }
        .no-data { text-align: center; color: #888; padding: 40px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📜 Speed Test History</h1>
        
        <div class="nav">
            <a href="/">📊 Overview</a>
            <a href="/history" class="active">📜 History</a>
        </div>

        <div class="section">
            <h2>Test History Files</h2>
            {% if history %}
            <ul class="history-list">
                {% for item in history %}
                <li class="history-item">
                    <div>
                        <span class="file">{{ item.name }}</span>
                        <span class="meta">{{ item.time }}</span>
                    </div>
                    <div>
                        <span class="size">{{ item.size }}</span>
                    </div>
                </li>
                {% endfor %}
            </ul>
            {% else %}
            <div class="no-data">No history files found.</div>
            {% endif %}
        </div>
    </div>
</body>
</html>
"""


def parse_csv_file(filepath):
    """Parse a CSV speed test result file."""
    results = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            next(reader, None)  # Skip header
            for row in reader:
                if len(row) >= 6:
                    try:
                        ip = row[0].strip()
                        speed = float(row[1].strip()) if row[1].strip() else 0
                        latency = row[2].strip()
                        loss = row[3].strip() if len(row) > 3 else "0"
                        
                        # Determine speed class
                        if speed >= 200:
                            speed_class = "speed-high"
                        elif speed >= 100:
                            speed_class = "speed-medium"
                        else:
                            speed_class = "speed-low"
                        
                        results.append({
                            'ip': ip,
                            'speed': speed,
                            'speed_class': speed_class,
                            'latency': latency,
                            'loss': loss
                        })
                    except (ValueError, IndexError):
                        continue
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
    return results


def get_log_files():
    """Get all CSV log files with metadata."""
    if not os.path.exists(LOG_DIR):
        return []
    
    files = []
    for filepath in glob.glob(os.path.join(LOG_DIR, "*.csv")):
        stat = os.stat(filepath)
        filename = os.path.basename(filepath)
        # Extract region and port from filename like HK-443.csv
        parts = filename.replace('.csv', '').split('-')
        region = parts[0] if len(parts) > 0 else 'Unknown'
        port = parts[1] if len(parts) > 1 else '443'
        
        files.append({
            'name': filename,
            'path': filepath,
            'time': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S'),
            'size': f"{stat.st_size / 1024:.1f} KB",
            'region': region,
            'port': port
        })
    
    return sorted(files, key=lambda x: x['time'], reverse=True)


def get_best_ips_per_region():
    """Get the best IP (highest speed) for each region."""
    log_files = get_log_files()
    best_ips = []
    all_results = []
    regions = set()
    
    for file_info in log_files:
        results = parse_csv_file(file_info['path'])
        for r in results:
            r['region'] = file_info['region']
            r['port'] = file_info['port']
            r['time'] = file_info['time']
            all_results.append(r)
        
        if results:
            best = max(results, key=lambda x: x['speed'])
            best['region'] = file_info['region']
            best['port'] = file_info['port']
            best_ips.append(best)
            regions.add(file_info['region'])
    
    # Sort by region
    best_ips.sort(key=lambda x: x['region'])
    return best_ips, all_results, len(log_files), len(all_results), len(regions)


@app.route('/')
def index():
    """Main dashboard page."""
    best_ips, all_results, total_tests, total_ips, regions = get_best_ips_per_region()
    log_files = get_log_files()
    last_update = log_files[0]['time'] if log_files else 'N/A'
    
    return render_template_string(HTML_TEMPLATE,
        best_ips=best_ips,
        all_results=sorted(all_results, key=lambda x: x['time'], reverse=True),
        total_tests=total_tests,
        total_ips=total_ips,
        regions=regions,
        last_update=last_update
    )


@app.route('/history')
def history():
    """History page showing all test files."""
    log_files = get_log_files()
    return render_template_string(HISTORY_TEMPLATE, history=log_files)


@app.route('/api/results')
def api_results():
    """JSON API for all results."""
    _, all_results, total_tests, total_ips, regions = get_best_ips_per_region()
    return jsonify({
        'total_tests': total_tests,
        'total_ips': total_ips,
        'regions': regions,
        'results': all_results
    })


if __name__ == '__main__':
    print("=" * 50)
    print("CF Speed Test Dashboard")
    print("Access at: http://0.0.0.0:5001")
    print("=" * 50)
    app.run(host='0.0.0.0', port=5001, debug=False)
