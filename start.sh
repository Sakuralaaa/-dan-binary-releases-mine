#!/bin/bash
# 专为 Codespace 云端环境定制的一键启动脚本
# 包含 Python 格式转换代理 + 注册机核心运行

echo "=========================================="
echo "准备运行环境..."
echo "=========================================="

# 1. 安装代理需要的 Python 依赖 (解决环境隔离报错)
python3 -m venv proxy_env
source proxy_env/bin/activate
pip install requests urllib3 -q

# 2. 生成中转代理脚本
cat << 'EOF' > upload_proxy.py
import json
import logging
from http.server import BaseHTTPRequestHandler, HTTPServer
import requests
import urllib3

urllib3.disable_warnings()

REAL_CPA_BASE_URL = "https://cli-proxy-api-plus-latest-n13w.onrender.com"

logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(message)s')

class UploadProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # 拦截 /v0/management/domains 请求，直接返回成功，因为很多 CPA 面板没有这个接口
        if "/v0/management/domains" in self.path:
            try:
                # 动态从冰佬真实的接口拉取当前支持的邮箱域名列表
                headers = {"Authorization": "Bearer linuxdo"}
                resp = requests.get("https://gpt-up.icoa.pp.ua/v0/management/domains", headers=headers, timeout=10)
                
                # 解析获取到的 json，并过滤出只有 .com 结尾的域名
                data = resp.json()
                com_domains = [d for d in data.get("domains", []) if d.endswith(".com")]
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"domains": com_domains}).encode('utf-8'))
                logging.info(f"✅ 动态获取 domains 成功，已过滤出 .com 域名共 {len(com_domains)} 个")
            except Exception as e:
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                # 如果拉取失败，给几个备用的 .com 域名兜底
                self.wfile.write(b'{"domains": ["*.mail.ultramandsb.com", "*.mail.linkjrzl.com", "*.mail.truerealbill.com"]}')
                logging.error(f"❌ 动态获取 domains 失败，使用备用 .com 域名: {e}")
            return

        # 其他 GET 请求透明转发
        try:
            url = f"{REAL_CPA_BASE_URL}{self.path}"
            headers = {k: v for k, v in self.headers.items() if k.lower() != 'host'}
            resp = requests.get(url, headers=headers, verify=False, timeout=30)
            self.send_response(resp.status_code)
            for k, v in resp.headers.items():
                if k.lower() not in ['transfer-encoding', 'content-encoding']:
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(resp.content)
        except Exception as e:
            logging.error(f"GET Proxy Error: {e}")
            self.send_response(500)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        auth_header = self.headers.get('Authorization')
        
        # 拦截 /auth-files 上传，转换格式
        if "/v0/management/auth-files" in self.path:
            try:
                token_data = json.loads(post_data.decode('utf-8'))
                email = token_data.get("email", "unknown_email")
                logging.info(f"[*] 收到 Token: {email}")
                
                filename = f"{email}.json"
                content = json.dumps(token_data, ensure_ascii=False).encode("utf-8")
                
                upload_url = f"{REAL_CPA_BASE_URL}/v0/management/auth-files"
                headers = {}
                if auth_header:
                    headers["Authorization"] = auth_header
                    
                # 使用 multipart/form-data 格式上传到真实的 CPA
                files = {"file": (filename, content, "application/json")}
                resp = requests.post(upload_url, files=files, headers=headers, verify=False, timeout=30)
                
                if 200 <= resp.status_code < 300:
                    logging.info(f"✅ 成功转换为文件并上传到云端 CPA ({resp.status_code})")
                else:
                    logging.error(f"❌ 上传到云端失败: HTTP {resp.status_code} - {resp.text}")

                self.send_response(resp.status_code)
                for k, v in resp.headers.items():
                    if k.lower() not in ['transfer-encoding', 'content-encoding']:
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp.content)
                
            except Exception as e:
                logging.error(f"❌ 代理处理异常: {e}")
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            # 其它 POST 请求透明转发
            try:
                url = f"{REAL_CPA_BASE_URL}{self.path}"
                headers = {k: v for k, v in self.headers.items() if k.lower() != 'host'}
                resp = requests.post(url, data=post_data, headers=headers, verify=False, timeout=30)
                self.send_response(resp.status_code)
                for k, v in resp.headers.items():
                    if k.lower() not in ['transfer-encoding', 'content-encoding']:
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp.content)
            except Exception as e:
                logging.error(f"POST Proxy Error: {e}")
                self.send_response(500)
                self.end_headers()

if __name__ == '__main__':
    server_address = ('0.0.0.0', 8000)
    httpd = HTTPServer(server_address, UploadProxyHandler)
    logging.info(f"CPA 格式转换代理已启动 -> 监听 0.0.0.0:8000 -> 转发至 {REAL_CPA_BASE_URL}")
    httpd.serve_forever()
EOF

# 3. 杀掉以前可能残留的进程，防止冲突
pkill -f "upload_proxy.py"
pkill -f "dan-web"

# 4. 后台运行中转代理
echo "启动格式转换代理 (后台运行)..."
nohup proxy_env/bin/python upload_proxy.py > proxy.log 2>&1 &
sleep 2

# 5. 启动冰佬的注册机 (单线程，并且把代理通过 default-proxy 参数传入)
echo "下载并启动 dan-web 注册机 (后台运行，单线程代理测试)..."

# 【核心修复】：必须配置 NO_PROXY，否则注册机连本地的 127.0.0.1 中转代理也会走 1024proxy！
# 1024proxy 出于安全限制（防 SSRF）会直接拒绝访问本地 IP，导致报 127.0.0.1:8000 is ban
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="127.0.0.1,localhost"

curl -fsSL https://raw.githubusercontent.com/uton88/dan-binary-releases/main/install.sh | bash -s -- \
    --install-dir "$HOME/dan-runtime" \
    --background \
    --cpa-base-url 'http://127.0.0.1:8000/' \
    --cpa-token '594926' \
    --mail-api-url 'https://gpt-mail.icoa.pp.ua/' \
    --mail-api-key 'linuxdo' \
    --threads 1 \
    --default-proxy 'http://ijvc19373-region-US-sid-1uRUGMEw-t-60:tarkyygw@us.1024proxy.io:3000'

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