Zero Downtime Deployment


# How it works

This follows a very simple concept:

We have a running instance _'A'_ and another one _'B'_ standing by.
Once the deployment on _'B'_ is completed, traffic is switched over and _'A'_ can be shut down.

A load balancer (such as nginx) is responsible for switching traffic.

![graph](https://i.imgur.com/NOcG42O.png)

# Usage

```shell
./deploy.sh deploy [COMMIT]
./deploy.sh rollback
./deploy.sh start <APP_NAME> <APP_DIR> <PORT>
./deploy.sh stop <APP_NAME>
```

# nginx config

```nginx
upstream my_app {
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
}

server {
    listen 80;
    server_name crafatar.com;
    location / {
        proxy_pass http://my_app;
        …
    }
}
```

[upstream](http://wiki.nginx.org/NginxHttpUpstreamModule#upstream):
> Requests are distributed according to the servers in round-robin manner [...]  
If with an attempt at the work with the server error occurred, then the request will be transmitted to the following server

*(see [proxy_next_upstream](http://wiki.nginx.org/HttpProxyModule#proxy_next_upstream) for details)*

# Details

Let's assume *A* is currently active. All traffic will go to port 3001, where it's running.
Deployment will work as follows:

0. *B* (not running) is updated, built, and then started.
0. Once *B* has started successfully, nginx will automatically send 50% of new connections to port 3002.
0. After making sure *B* is running, *A* receives a `SIGTERM`.  
   That tells it to close the server and no longer accept connections.
0. At this point, all *new* connections are routed to *B*
0. *A* is still running until all running requests are answered. It is then shut down.
0. `next_deploy` will be set to *A*

For the next deployment, repeat the same steps with a and b swapped.

## Rollbacks

In case of trouble with the newly deployed app, we can just spin up *A* again and send `SIGTERM` to *B* to undo the whole thing.