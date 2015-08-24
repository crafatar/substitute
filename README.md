# How it works

This follows a very simple concept:

We have a running instance _'A'_ and another one _'B'_ standing by.  
Once the deployment on _'B'_ is completed, traffic is switched over and _'A'_ can be shut down.

A load balancer (such as nginx) is responsible for switching traffic.

![graph](https://i.imgur.com/3JCU7Qu.png)

# Usage

```shell
./substitute deploy [COMMIT]
./substitute rollback
./substitute start <APP_NAME> <APP_DIR> <HOST> <PORT>
./substitute stop <APP_NAME>
```

## config

Make sure that you copy `deploy/config.sample` to `deploy/config`.  
And don't forget to adjust it for your needs :)

## Script hooks

You can create custom scripts that will run on various events.  
Scripts are searched for in `deploy/scripts/{name}.sh`

Script names (in their typical order for a deployment):

- `begin`
- `pre_checkout`
- `pre_install`
- `post_install`
- `pre_start`
- `post_start`
- `running`
- `pre_stop`
- `post_stop`
- `end`

These scripts run in the context of the `substitute` script and you have access to its variables.  
Please note that the working directory varies. Refer to the source for details.  
You can use them for whatever you want, such as creating required folders or symlinks, updating your load balancer, or sending notifications. Be creative! :sunglasses:

# Details

Let's assume *A* is currently active. All traffic will go to port 3001, where it's running.  
Deployment works as follows:

0. *B* (not running) is updated, built, and then started.
0. After making sure *B* is running, the load balancer has to send new connections to port 3002.
0. *A* receives a `SIGTERM`.  
   That tells it to close the server and no longer accept new connections.  
   _(This has to be implemented in the application, see [below](#sigterm))_
0. At this point, all *new* connections are routed to *B*
0. *A* is still running until all running requests are answered. It is then shut down.
0. `next_deploy` is set to *A*

For the next deployment, repeat the same steps with a and b swapped.

## Rollbacks

In case of trouble with the newly deployed app, we can just spin up *A* again and send `SIGTERM` to *B* to undo the whole thing.

## SIGTERM

Your application needs to handle `SIGTERM` in the way it is expected by *substitute*.  

That is, your app will *reject new connections* but *complete running requests*.  
Your app must *shut down* at some time.

Here is a sample node.js implementation:

```JavaScript
var server = http.createServer(requestHandler).listen();
process.on("SIGTERM", function() {
  server.close(function() {
    // all connections were closed
    process.exit();
  });
  
  setTimeout(function() {
    // force quit after 30 seconds
    process.exit(1);
  }, 30000);
});
```

# Example

## nginx config

```nginx
include /var/lib/my_app/nginx-upstream.conf;

server {
    listen 80;
    server_name my_app.com;
    location / {
        proxy_pass http://my_app;
        proxy_set_header Host $host;
        …
    }
}
```

## Script Hook

Create `deploy/scripts/running.sh`:

```bash
#!/usr/bin/env bash

set -e

info "Switching nginx upstream to port ${port}"
cat <<EOF > /var/lib/my_app/nginx-upstream.conf
upstream my_app {
    server 127.0.0.1:${port};
}
EOF
info "Reloading nginx..."
serivice nginx reload
info "nginx reload successful."
```