"""Builds docs/report.html (self-contained: diagrams, charts and log excerpts embedded)."""
import base64
import html
import pathlib
import re

R = pathlib.Path(__file__).resolve().parent.parent
REPO = "https://github.com/Wadri02/cloud-patterns-yawar"


def img(path, alt, kind):
    data = base64.b64encode((R / path).read_bytes()).decode()
    return f'<figure><img alt="{alt}" src="data:{kind};base64,{data}"><figcaption>{alt}</figcaption></figure>'


def svg(name, alt):
    return img(f"docs/diagrams/{name}.svg", alt, "image/svg+xml")


def log(path, pattern=None, limit=40, after=None):
    text = (R / path).read_text()
    if after:
        text = text[text.index(after):]
    lines = text.splitlines()
    if pattern:
        lines = [l for l in lines if re.search(pattern, l)]
    return f'<pre class="log">{html.escape(chr(10).join(lines[:limit]))}</pre>'


def ev(name, pattern=None, limit=30, cmd=""):
    """Excerpt of evidence/aws/<name>.log if the student already ran the script, else a placeholder."""
    for target in ("aws", "local"):
        f = R / "evidence" / target / f"{name}.log"
        if f.exists():
            return f'<p class="meta">Evidence ({target}): <code>evidence/{target}/{name}.log</code></p>' + log(f"evidence/{target}/{name}.log", pattern, limit)
    return f'<div class="box pending">Evidence pending — run <code>{cmd}</code>; it writes <code>evidence/aws/{name}.log</code> and this report embeds it when rebuilt (<code>python3 docs/build_report.py</code>).</div>'


def ev_img(path, alt):
    return img(path, alt, "image/png") if (R / path).exists() else ""


T = []  # (id, title, html)

T.append(("cb", "1. Circuit Breaker Pattern", f"""
<h3>What is it?</h3>
<p>A circuit breaker is a stateful proxy placed around a remote call. When the callee fails repeatedly, the breaker
<b>opens</b> and rejects further calls immediately, so the caller stops wasting threads and time on a service that is
known to be unhealthy, and the failing service gets room to recover. Its purpose is to <b>stop cascading failures</b>
and to <b>fail fast with a fallback</b>. The pattern was popularised by Nygard (2018) and is described in the AWS and
Azure pattern catalogues.</p>
<h3>How does it work?</h3>
<p>It is a finite-state machine with three states. <b>CLOSED</b>: calls pass and failures are counted (consecutive
count or failure rate over a sliding window). When the threshold is reached it moves to <b>OPEN</b>: calls are
short-circuited and the fallback (cached value, default response, queued request) is returned. After a
<i>wait duration</i> it moves to <b>HALF_OPEN</b>, where a limited number of trial calls are allowed; success closes
the circuit, failure opens it again. Components: the state store, the failure counter/window, a clock, the fallback,
and metrics/events for monitoring.</p>
{svg("01-circuit-breaker", "Figure 1. Circuit breaker states and call path")}
<h3>Where can it be implemented?</h3>
<ul><li>Synchronous service-to-service calls in microservices (REST/gRPC/Feign clients).</li>
<li>Calls to third-party APIs (payment, SMS/Telegram, maps) and to databases or caches.</li>
<li>At the edge: API gateways and service meshes (Istio/Envoy outlier detection) apply it per route.</li></ul>
<h3>Who uses it?</h3>
<p>Netflix created <b>Hystrix</b> for its streaming platform; Hystrix is now in maintenance mode and Spring Cloud
recommends <b>Resilience4j</b> as the replacement (Netflix, 2018; Resilience4j, n.d.). Resilience4j, Polly (.NET),
Envoy/Istio and AWS App Mesh implement the pattern and are used across the industry.</p>
<h3>Implementation in the project</h3>
<p><b>Where:</b> <code>ms-requests</code> (Java 21, Spring Boot 4.1) calls <code>ms-inventory</code> through the ALB on
Amazon ECS Fargate. Two versions with identical settings (3 failures → OPEN, 1.5 s → HALF_OPEN, 1 trial call):
an <b>own implementation</b> (<code>resilience/CircuitBreaker.java</code>, a synchronized state machine with fallback to the
last known stock) and <b>Resilience4j</b> (<code>CircuitBreakerConfig</code> programmatically, plus
<code>@CircuitBreaker</code> + <code>application.yml</code> in <code>StockService</code>, via <code>resilience4j-spring-boot4</code>, as the production style for Yawar).
<code>GET /api/requests/demo/circuit-breaker?impl=custom|resilience4j</code> performs 30 calls while ms-inventory is
switched to <i>hang</i> during calls 6–21, first without and then with the breaker; every line is also written to
CloudWatch Logs. Verified result of the demo logic: ~8.0 s of waiting without the breaker vs ~2.5 s with it, and half
the requests reaching the failing service. JUnit: <code>CircuitBreakerTest</code> (5 tests).</p>
{ev_img("evidence/aws/circuit-breaker-latency.png", "Caller latency with and without circuit breaker (AWS run)")}{ev("01-circuit-breaker", r"###|call  ?(5|6|8|9|14|26) |breaker", 30, "./01-circuit-breaker/test.sh aws")}
"""))

T.append(("retry", "2. Retry Pattern", f"""
<h3>What is it?</h3>
<p>Retry transparently repeats an operation that failed because of a <b>transient</b> fault (a dropped connection,
a 503 during a deployment, throttling). Its purpose is to turn short glitches into successes without involving the
user. It must be <b>bounded</b> and <b>safe</b>: retries add load, so they are combined with backoff, jitter, a maximum
number of attempts and idempotent operations (AWS, n.d.-a; Brooker, 2015).</p>
<h3>How does it work?</h3>
<p>A retry policy defines: (1) <b>what</b> is retryable (5xx, 429, timeouts, connection errors — never 4xx business
errors); (2) <b>how long to wait</b>: exponential backoff <code>base·2^attempt</code> capped at a maximum, plus
<b>jitter</b> (a random part, e.g. <i>full jitter</i> = random(0, backoff)) to de-synchronise clients;
(3) <b>how many</b> attempts; (4) honouring server hints such as <code>Retry-After</code>; and (5) for writes, an
<b>idempotency key</b> so a repeated request is not executed twice.</p>
{svg("02-retry", "Figure 3. Retry with backoff and jitter")}
<h3>Where can it be implemented?</h3>
<ul><li>HTTP/gRPC clients between microservices; message consumers (redelivery with delay, dead-letter queues).</li>
<li>Cloud SDK calls (AWS SDKs retry with backoff and jitter by default); Step Functions <code>Retry</code> blocks.</li>
<li>CI/CD steps and infrastructure scripts that call flaky endpoints.</li></ul>
<h3>Who uses it?</h3>
<p>Amazon documents exponential backoff with jitter as the standard for its own services and SDKs (Brooker, 2015;
AWS, n.d.-a). Stripe and other payment APIs require idempotency keys so clients can retry safely. Resilience4j Retry,
Polly and Google Cloud client libraries provide ready-made policies, and since Spring Framework 7 (Spring Boot 4)
retry is built into the framework itself with <code>@Retryable</code> and <code>@ConcurrencyLimit</code> (InfoQ, 2025).</p>
<h3>Implementation in the project</h3>
<p><code>resilience/Retry.java</code> (own: exponential backoff, full jitter, cap, max attempts, selective retry of
<code>RetryableException</code>, <code>Retry-After</code>) and Resilience4j <code>Retry</code> with
<code>IntervalFunction.ofExponentialRandomBackoff</code>. <code>ms-inventory</code> keeps an <code>Idempotency-Key</code>
store so a retried POST is not executed twice. <code>GET /api/requests/demo/retry?impl=…</code> runs five scenarios:
two 503s then success, a 400 that is not retried, a permanent outage that gives up after 4 attempts, a POST whose
response is lost (2 records without key, 1 with key) and a 200-client simulation (peak 200 vs ~70–85 requests per
window with jitter). JUnit: <code>RetryTest</code> (6 tests).</p>
{ev("02-retry", r"###|attempt|result|stored|failed fast|Exhausted|peak", 40, "./02-retry/test.sh aws")}
"""))

T.append(("timeout", "3. Timeout Pattern", f"""
<h3>What is it?</h3>
<p>A timeout sets the maximum time a caller will wait for an operation. Many failures do not appear as errors but as
requests that never finish; without a timeout every hung call holds a thread, a connection and memory until the
caller itself collapses. The purpose is to <b>bound waiting and release resources</b> so the system can apply a
fallback, a retry or a circuit breaker (Brooker, 2019).</p>
<h3>How does it work?</h3>
<ul><li><b>Connect timeout</b>: time to establish the TCP/TLS connection. <b>Read (socket) timeout</b>: maximum gap while
waiting for response bytes. <b>Overall timeout / time limiter</b>: limit for the whole operation.</li>
<li><b>Deadline propagation</b>: the entry point fixes a total budget and passes the <i>remaining</i> time to each
downstream hop (as gRPC deadlines do); a service that cannot finish in time refuses immediately instead of doing
useless work.</li>
<li>Values are chosen from measured latency (e.g. downstream p99.9) and must shrink from the edge inwards.</li></ul>
{svg("03-timeout", "Figure 5. Deadline propagation across two hops")}
<h3>Where can it be implemented?</h3>
<p>Every network call (HTTP clients, JDBC drivers, Redis, message brokers), load balancers and gateways (idle and
integration timeouts — e.g. Amazon API Gateway has a maximum integration timeout), serverless functions (Lambda
timeout setting), and any blocking call wrapped in a time limiter.</p>
<h3>Who uses it?</h3>
<p>Amazon describes choosing timeouts from latency percentiles and an acceptable false-timeout rate (Brooker, 2019);
Google's gRPC makes deadlines a first-class concept; Envoy/Istio, NGINX and AWS load balancers expose request and
idle timeouts; Resilience4j provides a TimeLimiter for Spring Boot services.</p>
<h3>Implementation in the project</h3>
<p><code>InventoryClient</code> (java.net.http) sets a connect timeout and a per-request timeout on every call;
<code>Timeouts.call()</code> (own) and Resilience4j <code>TimeLimiter</code> bound any blocking call; a
<code>Deadline</code> of 1000 ms is propagated in <code>X-Deadline-Ms</code> and <code>ms-inventory</code> answers 504
immediately when the remaining budget is too short. <code>GET /api/requests/demo/timeout?impl=…</code>: 12 calls to a
hanging service with 4 threads take ~6 s without timeout vs ~1.5 s with 0.5 s; with deadline propagation the request
ends in ~450 ms instead of ~1000 ms. JUnit: <code>TimeoutTest</code> (3 tests).</p>
{ev("03-timeout", None, 40, "./03-timeout/test.sh aws")}
"""))

T.append(("compute", "4. Serverless Computing and Docker Containers (AWS Lambda, Amazon ECS)", f"""
<h3>What is it?</h3>
<p><b>Serverless computing</b> (Function-as-a-Service) runs code in response to events without the developer
managing servers; the provider scales from zero to thousands of instances and bills per request and execution time.
<b>AWS Lambda</b> is Amazon's FaaS. <b>Docker containers</b> package an application with its runtime and dependencies
into a portable image; <b>Amazon ECS</b> is AWS's container orchestrator, which runs containers on EC2 instances or on
<b>AWS Fargate</b> (serverless containers, no instances to manage). Both aim to raise the abstraction level above VMs;
they differ in control, execution model and cost model.</p>
<h3>How does it work?</h3>
<ul><li><b>Lambda</b>: code + handler + configuration (memory, timeout, IAM role). An <i>event source</i> (API Gateway,
S3, SQS, EventBridge…) invokes it. The service creates an <i>execution environment</i> (INIT phase = cold start), reuses
it for later invocations (warm), and scales by running more environments in parallel. Limits: 15 min per invocation,
stateless.</li>
<li><b>ECS</b>: an image stored in <b>Amazon ECR</b>; a <i>task definition</i> (image, CPU, memory, ports, health check,
logging, IAM role); a <i>service</i> that keeps N tasks running, replaces unhealthy ones and registers them in an ALB
target group; the <i>cluster</i> and the launch type (EC2 or Fargate).</li></ul>
{svg("04-serverless-containers", "Figure 6. Lambda (event-driven) and ECS on Fargate (long-running) in Yawar")}
<h3>Where can it be implemented?</h3>
<table><tr><th></th><th>AWS Lambda</th><th>Amazon ECS (Fargate)</th></tr>
<tr><td>Best fit</td><td>Events, webhooks, schedulers, file processing, glue code, spiky traffic</td><td>Long-running APIs, microservices with steady traffic, any language/runtime</td></tr>
<tr><td>Duration</td><td>≤ 15 min per call</td><td>Unlimited</td></tr>
<tr><td>Scaling</td><td>Per request, to zero</td><td>Tasks with auto scaling (usually min ≥ 1)</td></tr>
<tr><td>Billing</td><td>Requests + GB-ms of execution</td><td>vCPU and memory per second while running</td></tr>
<tr><td>Trade-off</td><td>Cold starts, limited control</td><td>Must build images and manage services</td></tr></table>
<h3>Who uses it?</h3>
<p>Lambda: iRobot runs the backend of connected Roomba vacuums on Lambda and AWS IoT; FINRA analyses billions of
market events per day; Coca-Cola Freestyle built a touchless pouring experience on a serverless stack (AWS, n.d.-b,
n.d.-c). ECS/Fargate: United Airlines, Smartsheet, Flywire and the Fire TV team at Amazon Prime Video run production
workloads on ECS with Fargate (AWS, n.d.-d).</p>
<h3>Implementation in the project</h3>
<p><b>Lambda (Python 3.14)</b> <code>blood-stock-alert</code>: flags blood types under 5 units; triggered by an API Gateway
HTTP API (<code>POST /stock-alerts</code>) and an EventBridge <code>rate(1 hour)</code> rule; deployed with Terraform
using AWS Academy's <code>LabRole</code>; pytest (4 tests). <b>ECS on Fargate (Java)</b>: the three Spring Boot services
are built with a multi-stage Dockerfile (Maven → JRE 21), pushed to Amazon ECR and run as Fargate services
(0.5 vCPU / 1 GB) behind the ALB; an injected failure makes <code>/actuator/health</code> return DOWN, the target group
marks the task unhealthy and ECS starts a replacement (self-healing).</p>
{ev("04-lambda", r"###|coldStart|HTTP|REPORT|INIT", 20, "./04-serverless-and-containers/lambda/deploy-and-test.sh")}{ev("04-ecs", r"###|ms-|unhealthy|healthy|started|chaos", 40, "./04-serverless-and-containers/ecs/test-aws.sh")}
"""))

T.append(("edge", "5. API Gateway, Load Balancer and Reverse Proxy", f"""
<h3>What is it?</h3>
<p>All three sit between clients and servers but solve different problems. A <b>reverse proxy</b> receives requests on
behalf of backend servers and hides them (TLS termination, caching, compression, static content). A <b>load
balancer</b> distributes requests among several healthy instances of the same service (availability and horizontal
scaling). An <b>API gateway</b> is an API-aware reverse proxy that is the single entry point to many services and applies
API policies: authentication, rate limiting, routing, request transformation, versioning and analytics.</p>
<h3>How does it work?</h3>
<ul><li><b>Reverse proxy</b>: accepts the connection, terminates TLS, may answer from cache or static files, adds
<code>X-Forwarded-*</code> headers and forwards to an upstream (NGINX, HAProxy, Envoy, CloudFront).</li>
<li><b>Load balancer</b>: a pool of targets, an algorithm (round-robin, least connections, hashing), active/passive
health checks; works at L4 (TCP, e.g. AWS NLB) or L7 (HTTP, e.g. AWS ALB).</li>
<li><b>API gateway</b>: route table (path/host → service), identity (API keys, JWT/OAuth2), quotas and rate limits
(token bucket), correlation IDs, transformations; e.g. Amazon API Gateway, Spring Cloud Gateway, Kong, Apigee.</li>
<li>They are usually layered: Client → reverse proxy/CDN → API gateway → load balancer → service replicas.</li></ul>
{svg("05-gateway-lb-proxy", "Figure 7. Layered edge implemented in the demo")}
<h3>Where can it be implemented?</h3>
<p>At the edge of any web or mobile backend; in front of microservices (one gateway for web, desktop and mobile
clients, or one per client type — Backend-for-Frontend); inside Kubernetes as Ingress controllers; between regions for
global load balancing.</p>
<h3>Who uses it?</h3>
<p>Netflix built <b>Zuul</b> as the front door for all device and website requests to its streaming backend (Netflix,
n.d.); NGINX and HAProxy power a large part of the web as reverse proxies and load balancers; AWS customers combine
CloudFront, ALB/NLB and Amazon API Gateway; Kong and Apache APISIX are API gateways built on NGINX.</p>
<h3>Implementation in the project</h3>
<p>Each role is played by the AWS service built for it (Terraform in <code>05-api-gateway-lb-reverse-proxy/</code>):
<b>CloudFront</b> as reverse proxy (HTTPS, origin hidden, <code>/api/inventory</code> cached 5 s per API key);
<b>Amazon API Gateway REST</b> as API gateway (<code>/api/{{proxy+}}</code> routing, two API keys — web-app and
hospital-hcam — and a usage plan of 1 req/s with burst 5); the <b>Application Load Balancer</b> of the platform as load
balancer (path rules, round robin over 3 <code>ms-donors</code> tasks, health checks). The test script proves 403
without key, the changing <code>X-Instance</code> header, <code>x-cache: Miss → Hit</code> and 429 when throttled.</p>
{ev("05-edge", None, 45, "./05-api-gateway-lb-reverse-proxy/deploy-and-test.sh")}
"""))

T.append(("hub", "6. Hub-and-Spoke Architecture", f"""
<h3>What is it?</h3>
<p>A topology in which every network or system (spoke) connects only to a central <b>hub</b>, instead of to every other
spoke (full mesh). With <i>n</i> spokes a mesh needs n(n−1)/2 links; hub-and-spoke needs <i>n</i>. The hub centralises
routing, security inspection and shared services, which simplifies management and auditing. AWS recommends preferring
hub-and-spoke over many-to-many meshes once more than two networks must be connected (AWS, n.d.-e).</p>
<h3>How does it work?</h3>
<p>In AWS the hub is a <b>Transit Gateway</b> (TGW): each VPC, VPN or Direct Connect attaches to it; <b>TGW route
tables</b> decide which attachments can reach which (association + propagation), allowing isolation such as
"partners may reach shared services but not each other". A <b>shared-services VPC</b> in the hub hosts DNS, logging,
egress/NAT, inspection firewalls or VPC endpoints used by all spokes. The same idea exists in integration
architectures (a message broker/ESB as hub between applications) and in Azure (hub VNet + peered spoke VNets).</p>
{svg("06-hub-and-spoke", "Figure 8. Hub-and-spoke with policy, as implemented")}
<h3>Where can it be implemented?</h3>
<p>Multi-account / multi-VPC cloud landing zones (one VPC per environment, team or microservice domain), hybrid cloud
(on-premises data centre + VPCs through one hub), partner connectivity, centralised egress and inspection, and
application integration hubs.</p>
<h3>Who uses it?</h3>
<p>It is the reference topology of AWS's multi-VPC whitepaper and of AWS Control Tower/Landing Zone network accounts
(AWS, n.d.-f), and of Microsoft's Azure hub-spoke reference architecture; airlines popularised the term for route
networks, and enterprises use it for integration (e.g. a RabbitMQ/Kafka hub between systems).</p>
<h3>Implementation in the project</h3>
<p>Terraform creates an <b>AWS Transit Gateway</b> with four attached VPCs (hub/shared, donors, inventory, hospital
partner) and two TGW route tables: <code>rt-internal</code> propagates every VPC; <code>rt-partner</code>, used by the
hospital, only knows the hub and inventory, so donor personal data is unreachable from the partner network. A t3.nano
probe in each VPC serves HTTP and tests the others at boot; the script reads the matrix from the instance consoles.
Expected: all paths OK except hospital ↔ donors.</p>
{ev("06-hub-and-spoke", r"###|rt-|10\\.|YAWAR", 30, "./06-hub-and-spoke/deploy-and-test.sh")}
"""))

T.append(("lift", "7. Lift-and-Shift Migration Strategy (On-premises → AWS)", f"""
<h3>What is it?</h3>
<p>Lift-and-shift (<b>rehost</b>) moves an application from its current environment to the cloud <b>without changing
its code or architecture</b>. It is one of the AWS "7 Rs" (retire, retain, rehost, relocate, repurchase, replatform,
refactor) (AWS, n.d.-g). Its purpose is speed and low risk: exit a data centre quickly, then optimise in the cloud
("migrate first, modernise later").</p>
<h3>How does it work?</h3>
<ol><li><b>Assess</b>: inventory servers, dependencies, ports, data and licences; choose an R per application.</li>
<li><b>Replicate</b>: copy servers or artefacts — with <b>AWS Application Migration Service (MGN)</b>, an agent
continuously replicates disks at block level into a staging area.</li>
<li><b>Launch/test</b>: start test instances (EC2 + EBS) and validate functionality, checksums and performance.</li>
<li><b>Cutover</b>: freeze writes, final delta sync, launch the production instance, switch DNS, keep a rollback path.</li>
<li><b>Optimise</b> after migration (right-size instances, add Auto Scaling, managed databases = replatform).</li></ol>
{svg("07-lift-and-shift", "Figure 9. Rehost phases implemented by migrate.sh")}
<h3>Where can it be implemented?</h3>
<p>Data-centre exits with deadlines, legacy or vendor applications whose code cannot be changed, large migrations of
many servers (VMware/Hyper-V/physical to EC2), disaster-recovery set-ups, and as the first step before refactoring.</p>
<h3>Who uses it?</h3>
<p>Coca-Cola moved from its own on-premises data centres to AWS in 2013 after 20 years of operating them (AWS, 2021);
AWS MGN and the Cloud Migration Factory are used for large rehost programmes, and AWS Prescriptive Guidance recommends
rehost, replatform, relocate and retire as the common strategies for large migrations (AWS, n.d.-g).</p>
<h3>Implementation in the project</h3>
<p>The source system is <code>legacy-registry.jar</code> (plain Java 21, JDK HTTP server, CSV data, config file) running on
the student's machine as the on-premises server. <code>migrate-to-aws.sh</code> executes assess → replicate (bundle with
SHA-256 to S3) → launch (EC2 Amazon Linux 2023 + Amazon Corretto 21 + the same systemd unit, via Terraform) → test
(<code>GET /about</code> returns the SHA-256 of the running JAR, which must equal the on-prem one; identical
<code>GET /donors</code>) → cutover (late write, freeze, delta sync over SSH, new write on AWS, DNS switch).</p>
{ev("07-lift-and-shift", r"###|sha256|RESULT|records|write|DNS|site", 30, "./07-lift-and-shift/migrate-to-aws.sh")}
"""))

T.append(("bastion", "8. Bastion Host", f"""
<h3>What is it?</h3>
<p>A bastion (jump host) is a hardened server placed in a public subnet that is the <b>only</b> entry point for
administrators into resources in private subnets. Private servers accept SSH/RDP only from the bastion, so their attack
surface is not exposed to the internet, and all administrative access is concentrated in one point that can be
hardened, monitored and audited.</p>
<h3>How does it work?</h3>
<ul><li>Network: bastion in a public subnet with a public IP; workloads in private subnets without public IPs.</li>
<li>Firewall: bastion security group allows port 22 only from the administrators' IP ranges; private security groups
allow 22 only <i>from the bastion's security group</i>.</li>
<li>Access: <code>ssh -J bastion private-host</code> (ProxyJump) or port forwarding <code>ssh -L</code>; keys never
stored on the bastion (agent forwarding disabled), MFA, session logging.</li>
<li>Modern alternative on AWS: <b>Systems Manager Session Manager</b> provides shell/port-forwarding with IAM control
and logging and no inbound ports at all; AWS's startup security baseline recommends it over bastions (AWS, n.d.-h).</li></ul>
{svg("08-bastion", "Figure 10. Bastion host access path")}
<h3>Where can it be implemented?</h3>
<p>Administering EC2 instances, databases (tunnel to RDS/PostgreSQL), Kubernetes nodes or internal dashboards in
private subnets; on-premises DMZs; any environment where operators need occasional privileged access.</p>
<h3>Who uses it?</h3>
<p>It is a standard component of AWS reference architectures (e.g. Linux bastion host Quick Start) and of Azure
(Azure Bastion as a managed service) and Google Cloud (IAP TCP forwarding as a bastion-less alternative); many companies
are replacing self-managed bastions with Session Manager (AWS, n.d.-h).</p>
<h3>Implementation in the project</h3>
<p>Terraform builds a VPC with a public subnet (bastion t3.nano, SSH only from the administrator's /32, egress only to the
VPC, IMDSv2) and a private subnet (<code>ms-donors-db</code>, no public IP, SSH/8080 allowed only from the bastion's
security group). The script shows that the private host is unreachable directly, runs a command on it by jumping
through the bastion, forwards <code>localhost:9090</code> to it, and prints the sshd audit trail of the bastion.</p>
{ev("08-bastion", None, 40, "./08-bastion/deploy-and-test.sh")}
"""))

REFS = [
    "Amazon Web Services. (n.d.-a). <i>REL05-BP03 Control and limit retry calls</i>. AWS Well-Architected Framework. https://docs.aws.amazon.com/wellarchitected/latest/framework/rel05-bp03.html",
    "Amazon Web Services. (n.d.-b). <i>AWS Lambda customer case studies</i>. https://aws.amazon.com/lambda/resources/customer-case-studies/",
    "Amazon Web Services. (n.d.-c). <i>iRobot case study</i>. https://aws.amazon.com/solutions/case-studies/irobot/",
    "Amazon Web Services. (n.d.-d). <i>Amazon ECS customers</i>. https://aws.amazon.com/ecs/customers/",
    "Amazon Web Services. (n.d.-e). <i>REL02-BP04 Prefer hub-and-spoke topologies over many-to-many mesh</i>. AWS Well-Architected Framework. https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_planning_network_topology_prefer_hub_and_spoke.html",
    "Amazon Web Services. (n.d.-f). <i>Building a scalable and secure multi-VPC AWS network infrastructure: AWS Transit Gateway</i>. https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/transit-gateway.html",
    "Amazon Web Services. (n.d.-g). <i>About the migration strategies</i>. AWS Prescriptive Guidance. https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html",
    "Amazon Web Services. (n.d.-h). <i>WKLD.06 – Use Systems Manager instead of SSH or RDP</i>. AWS Startup Security Baseline. https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-startup-security-baseline/wkld-06.html",
    "Amazon Web Services. (2021). <i>See how Coca-Cola uses the compute power of AWS to innovate consumer beverage experiences at scale</i>. AWS for Industries Blog. https://aws.amazon.com/blogs/industries/see-how-coca-cola-uses-the-compute-power-of-aws-to-innovate-consumer-beverage-experiences-at-scale",
    "Brooker, M. (2015). <i>Exponential backoff and jitter</i>. AWS Architecture Blog. https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/",
    "Brooker, M. (2019). <i>Timeouts, retries, and backoff with jitter</i>. The Amazon Builders' Library. https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/",
    "InfoQ. (2025, November). <i>Spring Framework 7 and Spring Boot 4 deliver API versioning, resilience, and null-safe annotations</i>. https://www.infoq.com/news/2025/11/spring-7-spring-boot-4",
    "Netflix. (2018). <i>Hystrix: README – Hystrix status</i> [Computer software]. GitHub. https://github.com/Netflix/Hystrix",
    "Netflix. (n.d.). <i>Zuul wiki</i> [Computer software]. GitHub. https://github.com/Netflix/zuul/wiki",
    "Nygard, M. T. (2018). <i>Release it! Design and deploy production-ready software</i> (2nd ed.). Pragmatic Bookshelf.",
    "Resilience4j. (n.d.). <i>Resilience4j documentation</i>. https://resilience4j.readme.io/",
]

COMPARE = """
<table><tr><th>Pattern / technology</th><th>Main problem solved</th><th>Layer</th><th>Use in Yawar</th></tr>
<tr><td>Circuit breaker</td><td>Cascading failures</td><td>Client code / gateway</td><td>ms-requests → ms-inventory, Telegram API</td></tr>
<tr><td>Retry</td><td>Transient faults</td><td>Client code / SDK</td><td>Idempotent reads, donations with Idempotency-Key</td></tr>
<tr><td>Timeout</td><td>Hung calls, resource exhaustion</td><td>Every remote call</td><td>Feign/WebClient timeouts, deadline from the gateway</td></tr>
<tr><td>Lambda / ECS</td><td>Where code runs</td><td>Compute</td><td>Alerts on Lambda; Spring Boot services in containers</td></tr>
<tr><td>API gateway / LB / reverse proxy</td><td>Entry, distribution, protection</td><td>Edge (L4–L7)</td><td>Single API Gateway for web, desktop and mobile</td></tr>
<tr><td>Hub-and-spoke</td><td>Network sprawl, isolation</td><td>Network</td><td>Separate VPCs / namespaces per domain and for hospitals</td></tr>
<tr><td>Lift-and-shift</td><td>Fast migration</td><td>Migration strategy</td><td>Moving a legacy registry before refactoring</td></tr>
<tr><td>Bastion</td><td>Secure admin access</td><td>Network / security</td><td>Access to databases in private subnets (or Session Manager)</td></tr></table>
<p>The resilience patterns are complementary and are normally stacked: <b>Retry( CircuitBreaker( Timeout( call ) ) )</b>
— the timeout bounds each attempt, the breaker stops attempts when the service is clearly down, and the retry
absorbs isolated glitches. The edge components, the hub and the bastion work at the infrastructure level and are
defined as code (Terraform) so they can be recreated in another AWS account in minutes.</p>"""

nav = "".join(f'<a href="#{i}">{t.split(". ", 1)[0]}. {t.split(". ", 1)[1].split(" (")[0]}</a>' for i, t, _ in T)
sections = "".join(f'<section id="{i}"><h2>{t}</h2>{h}</section>' for i, t, h in T)
refs = "".join(f"<li>{r}</li>" for r in REFS)

page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cloud Architecture and Design Patterns — Research Report</title>
<style>
:root{{--bg:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--line:#e7e6e2;--accent:#2a78d6;--code:#f3f2ef}}
@media (prefers-color-scheme:dark){{:root{{--bg:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--line:#353532;--accent:#3987e5;--code:#262624}}
 figure img{{background:#fcfcfb;border-radius:8px;padding:6px}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}}
main{{max-width:860px;margin:0 auto;padding:20px 16px 60px}}
h1{{font-size:1.6rem;line-height:1.25;margin:.2em 0}} h2{{font-size:1.3rem;margin-top:2.2em;padding-top:.6em;border-top:1px solid var(--line)}}
h3{{font-size:1.02rem;margin:1.3em 0 .3em;color:var(--accent)}}
.meta{{color:var(--ink2);font-size:.92rem}}
nav{{display:flex;flex-wrap:wrap;gap:6px;margin:16px 0}} nav a{{font-size:.82rem;padding:5px 10px;border:1px solid var(--line);border-radius:999px;color:var(--ink);text-decoration:none}}
a{{color:var(--accent)}}
code{{background:var(--code);padding:1px 5px;border-radius:4px;font-size:.88em}}
pre.log{{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:10px;overflow-x:auto;font-size:.74rem;line-height:1.45;white-space:pre}}
figure{{margin:14px 0;text-align:center}} figure img{{max-width:100%;height:auto;max-height:420px}}
figcaption{{font-size:.82rem;color:var(--ink2);margin-top:4px}}
table{{border-collapse:collapse;width:100%;font-size:.86rem;display:block;overflow-x:auto}}
th,td{{border-bottom:1px solid var(--line);padding:7px 8px;text-align:left;vertical-align:top}} th{{color:var(--ink2);font-weight:600}}
.box{{border:1px solid var(--line);border-radius:10px;padding:12px 14px;margin:14px 0}}
.pending{{color:var(--ink2);font-size:.9rem;border-style:dashed}}
.refs li{{margin-bottom:8px;padding-left:2em;text-indent:-2em;list-style:none;word-break:break-word}} .refs{{padding:0}}
</style></head><body><main>
<p class="meta">Universidad Central del Ecuador (UCE) · Systems Engineering · Research assignment</p>
<h1>Cloud Architecture and Design Patterns</h1>
<p class="meta">Author: Adrian Lumbi · Case study: <b>Yawar</b>, a microservices platform for blood-donation management in Ecuador · November 2026</p>
<div class="box"><b>Repository:</b> <a href="{REPO}">{REPO}</a><br>
Each topic has its own folder with README, architecture diagram, source code, configuration (Docker Compose /
Terraform), tests and <code>evidence/</code> logs from a real execution. One command reproduces everything:
<code>./scripts/run-all.sh</code>.</div>
<nav>{nav}<a href="#comparison">Comparison</a><a href="#refs">References</a></nav>
<section><h2>Introduction</h2>
<p>Distributed systems fail partially: a dependency becomes slow, a replica crashes, a network path disappears. This
report studies eight patterns and technologies that address how cloud systems <b>survive failures</b> (circuit
breaker, retry, timeout), <b>run code</b> (serverless functions and containers), <b>receive and distribute traffic</b>
(API gateway, load balancer, reverse proxy), <b>organise networks and access</b> (hub-and-spoke, bastion) and
<b>reach the cloud</b> (lift-and-shift). For each one, five questions are answered — what, how, where, who, and how to
implement it — and the implementation is applied to Yawar's domain (donors, blood inventory, hospitals).</p>
<p><b>Implementation stack.</b> Backend in Java 21 + Spring Boot 4.1 (<code>ms-donors</code>, <code>ms-inventory</code>,
<code>ms-requests</code>) plus a framework-less legacy application; resilience patterns implemented twice (own code and
Resilience4j 2.4 with its Spring Boot 4 module); one AWS Lambda in Python 3.14; infrastructure as code with Terraform on AWS (ECR, ECS Fargate, ALB,
API Gateway, CloudFront, Lambda, EventBridge, Transit Gateway, EC2, S3) inside an AWS Academy Learner Lab.</p>
{svg("00-architecture", "Figure 0. Yawar deployment used for the practical part")}
<p class="meta"><b>Evidence.</b> Every deploy/test script writes its output to <code>evidence/aws/</code>; this report embeds
those logs when it is rebuilt with <code>python3 docs/build_report.py</code>.</p></section>
{sections}
<section id="comparison"><h2>Comparison and conclusions</h2>{COMPARE}</section>
<section id="refs"><h2>References</h2><ul class="refs">{refs}</ul></section>
</main></body></html>"""
(R / "docs" / "report.html").write_text(page)
print(f"report.html {len(page) // 1024} KB")
