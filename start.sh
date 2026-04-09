#!/bin/bash
# 专为 Codespace 云端环境定制的一键启动脚本
# 包含 Python 格式转换代理 + 注册机核心运行

echo "=========================================="
echo "准备运行环境..."
echo "=========================================="

# 1. 安装代理需要的 Python 依赖
pip install requests urllib3 -q

# 2. 生成中转代理脚本
cat << 'EOF' > upload_proxy.py
import json
import logging
from http.server import BaseHTTPRequestHandler, HTTPServer
import requests
import urllib3

urllib3.disable_warnings()

REAL_CPA_BASE_URL = "https://cli-proxy-api-plus-latest-n13w.onrender.com/"

logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(message)s')

class UploadProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        auth_header = self.headers.get('Authorization')
        
        try:
            token_data = json.loads(post_data.decode('utf-8'))
            email = token_data.get("email", "unknown_email")
            logging.info(f"[*] 收到 Token: {email}")
            
            filename = f"{email}.json"
            content = json.dumps(token_data, ensure_ascii=False).encode("utf-8")
            
            upload_url = f"{REAL_CPA_BASE_URL.rstrip('/')}/v0/management/auth-files"
            headers = {}
            if auth_header:
                headers["Authorization"] = auth_header
                
            # 使用 multipart/form-data 格式上传到真实的 CPA
            files = {"file": (filename, content, "application/json")}
            resp = requests.post(upload_url, files=files, headers=headers, verify=False, timeout=30)
            
            if 200 <= resp.status_code < 300:
                logging.info(f"✅ 成功转换为文件并上传到云端 CPA ({resp.status_code})")
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            else:
                logging.error(f"❌ 上传到云端失败: HTTP {resp.status_code} - {resp.text}")
                self.send_response(resp.status_code)
                self.end_headers()
                self.wfile.write(resp.content)
                
        except Exception as e:
            logging.error(f"❌ 代理处理异常: {e}")
            self.send_response(500)
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8000)
    httpd = HTTPServer(server_address, UploadProxyHandler)
    logging.info(f"CPA 格式转换代理已启动 -> 监听 127.0.0.1:8000 -> 转发至 {REAL_CPA_BASE_URL}")
    httpd.serve_forever()
EOF

# 3. 杀掉以前可能残留的进程，防止冲突
pkill -f "upload_proxy.py"
pkill -f "dan-web"

# 4. 后台运行中转代理
echo "启动格式转换代理 (后台运行)..."
nohup python3 upload_proxy.py > proxy.log 2>&1 &
sleep 2

# 5. 启动冰佬的注册机 (CPA 指向本地代理，密码使用你的 594926)
echo "下载并启动 dan-web 注册机 (后台运行)..."
curl -fsSL https://raw.githubusercontent.com/uton88/dan-binary-releases/main/install.sh | bash -s -- \
    --install-dir "$HOME/dan-runtime" \
    --background \
    --cpa-base-url 'http://127.0.0.1:8000/' \
    --cpa-token '594926' \
    --mail-api-url 'https://gpt-mail.icoa.pp.ua/' \
    --mail-api-key 'linuxdo' \
    --threads 20

echo ""
echo "=========================================="
echo "🚀 启动完成！两部分程序均已在后台运行。"
echo "=========================================="
echo "查看注册机刷号进度命令: tail -f $HOME/dan-runtime/dan-web.log"
echo "查看上传云端成功日志命令: tail -f proxy.log"
echo "=========================================="
echo "如果想停止程序，请运行："
echo "pkill -f upload_proxy.py && pkill -f dan-web"
echo "=========================================="