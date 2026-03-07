# Dashboard 状态获取机制

本文档详细描述 Dashboard 如何动态获取系统代理状态并展示参数。

---

## 1. 核心机制概述

Dashboard 通过两种方式获取数据：

| 方式 | 用途 | 特点 |
|------|------|------|
| **HTTP RESTful API** | 获取配置、节点、规则等静态数据 | 请求-响应模式 |
| **WebSocket** | 获取实时数据流（日志、流量、连接） | 持续推送 |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Dashboard (浏览器)                                 │
│                                                                              │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐      │
│   │   HTTP fetch    │     │   WebSocket     │     │   定时轮询      │      │
│   │  (一次性请求)   │     │  (实时推送)     │     │  (状态同步)     │      │
│   └────────┬────────┘     └────────┬────────┘     └────────┬────────┘      │
│            │                       │                       │               │
└────────────┼───────────────────────┼───────────────────────┼───────────────┘
             │                       │                       │
             ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Clash 内核 HTTP Server                               │
│                                                                              │
│   /api/proxies        /api/configs       /api/rules                         │
│   /api/connections    /api/logs (WS)     /api/traffic (WS)                  │
│   /api/providers      /api/version       ...                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. RESTful API 获取状态

### 2.1 核心 API 端点

| 端点 | 方法 | 用途 | 返回数据 |
|------|------|------|----------|
| `/api/version` | GET | 获取版本信息 | 版本号、Premium 状态 |
| `/api/configs` | GET | 获取配置信息 | 端口、模式、规则 |
| `/api/proxies` | GET | 获取代理节点 | 节点列表、延迟、选择状态 |
| `/api/providers/proxies` | GET | 获取代理提供者 | 订阅节点、更新时间 |
| `/api/rules` | GET | 获取规则列表 | 分流规则 |
| `/api/connections` | GET | 获取当前连接 | 连接详情、流量 |

### 2.2 代理节点数据结构

**请求**:
```http
GET /api/proxies HTTP/1.1
Host: 127.0.0.1:9090
Authorization: Bearer <secret>
```

**响应**:
```json
{
  "proxies": {
    "GLOBAL": {
      "type": "Selector",
      "now": "自动选择",
      "all": ["自动选择", "手动选择", "节点1", "节点2"]
    },
    "自动选择": {
      "type": "URLTest",
      "now": "香港-01",
      "all": ["香港-01", "香港-02", "日本-01"],
      "udp": true
    },
    "香港-01": {
      "type": "Vmess",
      "now": 120,
      "udp": true,
      "history": [
        {"time": "2025-01-15T10:00:00Z", "delay": 120},
        {"time": "2025-01-15T09:55:00Z", "delay": 115}
      ]
    }
  }
}
```

### 2.3 节点延迟测试

**请求**:
```http
GET /api/proxies/香港-01/delay?timeout=5000&url=https://www.gstatic.com/generate_204 HTTP/1.1
Host: 127.0.0.1:9090
Authorization: Bearer <secret>
```

**响应**:
```json
{
  "delay": 120
}
```

### 2.4 切换代理选择

**请求**:
```http
PUT /api/proxies/自动选择 HTTP/1.1
Host: 127.0.0.1:9090
Authorization: Bearer <secret>
Content-Type: application/json

{
  "name": "香港-01"
}
```

---

## 3. WebSocket 实时数据流

### 3.1 实时日志

```
┌──────────┐                                          ┌──────────────────┐
│ Dashboard │                                          │   Clash 内核     │
└────┬─────┘                                          └────────┬─────────┘
     │                                                         │
     │  WebSocket 连接                                         │
     │  ws://127.0.0.1:9090/logs?secret=xxx                    │
     │────────────────────────────────────────────────────────>│
     │                                                         │
     │                                    持续推送日志          │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     │  {"type":"info","payload":"[TCP] 127.0.0.1:12345 --> example.com:443"}
     │<════════════════════════════════════════════════════════│
     │                                                         │
     │  {"type":"info","payload":"[Rule] MATCH --> PROXY"}     │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     ▼                                                         ▼
```

**连接代码示例**:
```javascript
const ws = new WebSocket('ws://127.0.0.1:9090/logs?secret=xxx');

ws.onmessage = (event) => {
  const log = JSON.parse(event.data);
  // log.type: "info" | "warning" | "error"
  // log.payload: 日志内容
  console.log(`[${log.type}] ${log.payload}`);
};
```

### 3.2 实时流量统计

```
┌──────────┐                                          ┌──────────────────┐
│ Dashboard │                                          │   Clash 内核     │
└────┬─────┘                                          └────────┬─────────┘
     │                                                         │
     │  WebSocket 连接                                         │
     │  ws://127.0.0.1:9090/traffic?secret=xxx                 │
     │────────────────────────────────────────────────────────>│
     │                                                         │
     │                                    持续推送流量          │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     │  {"up":1024,"down":51200}    // bytes/s                 │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     │  {"up":2048,"down":102400}                              │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     ▼                                                         ▼
```

### 3.3 实时连接监控

```
┌──────────┐                                          ┌──────────────────┐
│ Dashboard │                                          │   Clash 内核     │
└────┬─────┘                                          └────────┬─────────┘
     │                                                         │
     │  WebSocket 连接                                         │
     │  ws://127.0.0.1:9090/connections?secret=xxx             │
     │────────────────────────────────────────────────────────>│
     │                                                         │
     │                                    连接变化时推送        │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     │  {                                                      │
     │    "downloadTotal": 1048576,                            │
     │    "uploadTotal": 524288,                               │
     │    "connections": [{                                    │
     │      "id": "abc123",                                    │
     │      "metadata": {                                      │
     │        "network": "tcp",                                │
     │        "type": "HTTP",                                  │
     │        "sourceIP": "127.0.0.1",                         │
     │        "destinationIP": "142.250.185.78",               │
     │        "sourcePort": "12345",                           │
     │        "destinationPort": "443",                        │
     │        "host": "www.google.com"                         │
     │      },                                                 │
     │      "upload": 1024,                                    │
     │      "download": 51200,                                 │
     │      "start": "2025-01-15T10:00:00Z",                   │
     │      "chains": ["香港-01", "自动选择"],                 │
     │      "rule": "MATCH"                                    │
     │    }]                                                   │
     │  }                                                      │
     │<════════════════════════════════════════════════════════│
     │                                                         │
     ▼                                                         ▼
```

---

## 4. Dashboard 前端实现

### 4.1 数据获取流程

```javascript
// 1. 获取所有代理节点
const fetchProxies = async () => {
  const response = await fetch('http://127.0.0.1:9090/api/proxies', {
    headers: {
      'Authorization': `Bearer ${secret}`
    }
  });
  const data = await response.json();
  return data.proxies;
};

// 2. 获取代理提供者（订阅节点）
const fetchProviders = async () => {
  const response = await fetch('http://127.0.0.1:9090/api/providers/proxies', {
    headers: {
      'Authorization': `Bearer ${secret}`
    }
  });
  return await response.json();
};

// 3. 测试节点延迟
const testLatency = async (proxyName, testUrl, timeout) => {
  const url = `http://127.0.0.1:9090/api/proxies/${encodeURIComponent(proxyName)}/delay?timeout=${timeout}&url=${encodeURIComponent(testUrl)}`;
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${secret}`
    }
  });
  return await response.json();  // { delay: 120 }
};

// 4. 切换代理
const selectProxy = async (groupName, proxyName) => {
  await fetch(`http://127.0.0.1:9090/api/proxies/${encodeURIComponent(groupName)}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${secret}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ name: proxyName })
  });
};
```

### 4.2 WebSocket 连接管理

```javascript
// 日志 WebSocket
const connectLogs = () => {
  const ws = new WebSocket(`ws://127.0.0.1:9090/logs?secret=${secret}`);

  ws.onmessage = (event) => {
    const log = JSON.parse(event.data);
    appendLog(log);  // 添加到日志列表
  };

  ws.onerror = (error) => {
    console.error('Logs WebSocket error:', error);
  };

  return ws;
};

// 流量 WebSocket
const connectTraffic = () => {
  const ws = new WebSocket(`ws://127.0.0.1:9090/traffic?secret=${secret}`);

  ws.onmessage = (event) => {
    const traffic = JSON.parse(event.data);
    updateTrafficDisplay(traffic.up, traffic.down);  // 更新流量显示
  };

  return ws;
};

// 连接监控 WebSocket
const connectConnections = () => {
  const ws = new WebSocket(`ws://127.0.0.1:9090/connections?secret=${secret}`);

  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    updateConnectionsList(data.connections);  // 更新连接列表
    updateTotalTraffic(data.downloadTotal, data.uploadTotal);
  };

  return ws;
};
```

### 4.3 状态管理（Pinia Store）

```javascript
// proxies store（简化版）
const useProxiesStore = defineStore('proxies', () => {
  const proxies = ref([]);           // 代理组列表
  const proxyProviders = ref([]);    // 代理提供者列表
  const latencyMap = ref({});        // 延迟映射

  // 获取所有代理
  const fetchProxies = async () => {
    const [providersRes, proxiesRes] = await Promise.all([
      fetch('/api/providers/proxies', { headers }),
      fetch('/api/proxies', { headers })
    ]);

    const providersData = await providersRes.json();
    const proxiesData = await proxiesRes.json();

    // 处理数据...
    proxies.value = processProxies(proxiesData.proxies);
    proxyProviders.value = processProviders(providersData.providers);
  };

  // 测试单个节点延迟
  const testProxyLatency = async (proxyName, testUrl, timeout) => {
    const result = await fetch(
      `/api/proxies/${proxyName}/delay?timeout=${timeout}&url=${testUrl}`,
      { headers }
    );
    const { delay } = await result.json();
    latencyMap.value[proxyName] = delay;
  };

  // 切换代理
  const selectProxyInGroup = async (group, proxyName) => {
    await fetch(`/api/proxies/${group}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify({ name: proxyName })
    });
    await fetchProxies();  // 刷新状态
  };

  return {
    proxies,
    proxyProviders,
    latencyMap,
    fetchProxies,
    testProxyLatency,
    selectProxyInGroup
  };
});
```

---

## 5. 数据展示参数

### 5.1 代理节点参数

| 参数 | 来源 | 说明 |
|------|------|------|
| `name` | `/api/proxies` | 节点名称 |
| `type` | `/api/proxies` | 节点类型 (Vmess/SS/Trojan) |
| `udp` | `/api/proxies` | 是否支持 UDP |
| `now` | `/api/proxies` | 当前选中的节点（代理组） |
| `delay` | `/api/proxies/{name}/delay` | 延迟（毫秒） |
| `history` | `/api/proxies` | 历史延迟记录 |

### 5.2 连接参数

| 参数 | 来源 | 说明 |
|------|------|------|
| `id` | WebSocket | 连接唯一标识 |
| `metadata.host` | WebSocket | 目标主机名 |
| `metadata.sourceIP` | WebSocket | 源 IP |
| `chains` | WebSocket | 代理链路 |
| `upload/download` | WebSocket | 上下行流量 |
| `rule` | WebSocket | 匹配规则 |

### 5.3 流量参数

| 参数 | 来源 | 说明 |
|------|------|------|
| `up` | WebSocket `/traffic` | 上行速度 (bytes/s) |
| `down` | WebSocket `/traffic` | 下行速度 (bytes/s) |
| `downloadTotal` | WebSocket `/connections` | 总下载量 |
| `uploadTotal` | WebSocket `/connections` | 总上传量 |

---

## 6. 完整数据流图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Dashboard 初始化                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. 读取配置                                                                 │
│     - config.js (defaultBackendURL)                                         │
│     - localStorage (用户设置)                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  2. 建立 API 连接                                                            │
│     - GET /api/version (验证连接)                                           │
│     - GET /api/configs (获取配置)                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  3. 获取初始数据                                                             │
│     ┌─────────────────────┐                                                 │
│     │ GET /api/proxies    │ ──> 解析代理组和节点                            │
│     └─────────────────────┘                                                 │
│     ┌─────────────────────┐                                                 │
│     │ GET /api/providers  │ ──> 解析订阅节点                                │
│     └─────────────────────┘                                                 │
│     ┌─────────────────────┐                                                 │
│     │ GET /api/rules      │ ──> 解析规则列表                                │
│     └─────────────────────┘                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  4. 建立 WebSocket 连接                                                      │
│     ┌─────────────────────┐                                                 │
│     │ ws://.../traffic    │ ──> 实时流量统计                                │
│     └─────────────────────┘                                                 │
│     ┌─────────────────────┐                                                 │
│     │ ws://.../logs       │ ──> 实时日志流                                  │
│     └─────────────────────┘                                                 │
│     ┌─────────────────────┐                                                 │
│     │ ws://.../connections│ ──> 实时连接监控                                │
│     └─────────────────────┘                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  5. 持续更新                                                                 │
│     - WebSocket 消息 ──> 更新 UI                                            │
│     - 用户操作 ──> API 调用 ──> 更新状态                                    │
│     - 定时刷新（可选）──> 重新获取数据                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. 用户操作流程

### 7.1 切换代理节点

```
用户点击节点
     │
     ▼
┌─────────────────────────────────────┐
│ PUT /api/proxies/{groupName}        │
│ Body: { "name": "香港-01" }         │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ Clash 内核更新选择                  │
│ - 修改内存中的选择状态              │
│ - 新连接使用新节点                  │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ Dashboard 刷新状态                  │
│ - GET /api/proxies                  │
│ - 更新 UI 显示                      │
└─────────────────────────────────────┘
```

### 7.2 测试节点延迟

```
用户点击测试按钮
     │
     ▼
┌─────────────────────────────────────┐
│ GET /api/proxies/{name}/delay       │
│ ?timeout=5000&url=https://...       │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ Clash 内核执行测试                  │
│ - 通过指定节点请求测试 URL          │
│ - 记录延迟时间                      │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ 返回延迟结果                        │
│ { "delay": 120 }                    │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│ Dashboard 更新显示                  │
│ - 更新延迟徽章                      │
│ - 更新延迟历史                      │
└─────────────────────────────────────┘
```

---

## 8. 认证机制

### 8.1 Secret 认证

所有 API 请求都需要认证：

```javascript
// 方式1：Authorization Header
fetch('/api/proxies', {
  headers: {
    'Authorization': `Bearer ${secret}`
  }
});

// 方式2：URL 参数
fetch(`/api/proxies?secret=${secret}`);

// 方式3：WebSocket 参数
const ws = new WebSocket(`ws://host/logs?secret=${secret}`);
```

### 8.2 Secret 获取流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Dashboard 加载                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                     ┌───────────────┼───────────────┐
                     │               │               │
                     ▼               ▼               ▼
              ┌──────────┐    ┌──────────┐    ┌──────────┐
              │ 用户输入 │    │ URL 参数 │    │ 本地存储 │
              │ (Setup页)│    │ ?secret= │    │localStorage│
              └──────────┘    └──────────┘    └──────────┘
                     │               │               │
                     └───────────────┼───────────────┘
                                     │
                                     ▼
                            存储到全局状态
                                     │
                                     ▼
                         后续请求携带 Secret
```

---

## 9. 错误处理

### 9.1 连接失败

```javascript
const fetchWithRetry = async (url, options, retries = 3) => {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url, options);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.json();
    } catch (error) {
      if (i === retries - 1) {
        showToast('连接失败，请检查 Clash 是否运行');
        throw error;
      }
      await new Promise(r => setTimeout(r, 1000 * (i + 1)));
    }
  }
};
```

### 9.2 WebSocket 重连

```javascript
class ReconnectingWebSocket {
  constructor(url) {
    this.url = url;
    this.connect();
  }

  connect() {
    this.ws = new WebSocket(this.url);

    this.ws.onclose = () => {
      console.log('WebSocket closed, reconnecting...');
      setTimeout(() => this.connect(), 3000);
    };

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      this.ws.close();
    };
  }
}
```
