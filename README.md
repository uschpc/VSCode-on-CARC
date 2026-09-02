# Using Visual Studio Code on CARC

To connect "Visual Studio Code" to a remote server, to edit files and run scripts there, we
have three major options: 
- Code Server in CARC OnDemand (The easiest option on compute nodes)
- SSH-FS Extension (Most compatible with login node restrictions)
- Remote-SSH Extension (Advanced, should be used on compute nodes)

Code Server runs on a compute node on the cluster and you can access it via your browser. On the other hand, Remote-SSH and SSH-FS both use
the VS Code already installed on your own computer, and they differ in how they interact with the cluster.

## Code Server in CARC OnDemand

The most straightforward option to use "Visual Studio Code" on the compute nodes is Code Server which can be accessed via a browser. CARC offers
the "Code Server" as an interactive app in OnDemand on both Discovery and Endeavour.

OnDemand submits your session as a Slurm job, so it is subject
to the same partition limits. You can have access to GPUs and more compute that can be accessed on a login node.

To start a session:

1. Sign in to CARC OnDemand.
2. Select **Code Server** from the **Interactive Apps** menu.
3. Fill in the session form: cluster, project account, partition, number of CPUs, memory, and
   number of hours. Leave memory blank for a default of 2 GB per core.
4. Click **Launch**. The session is queued like any other job.
5. When the session turns green on the **My Interactive Sessions** page, connect to it.

Delete the session with the red **Delete** button when you finish. It also ends by itself when the
hours you requested run out.

Code Server installs extensions from the Open VSX registry rather than the Microsoft Marketplace.
Claude Code is published there as `Anthropic.claude-code` and Codex as `openai.chatgpt`.

Nothing is installed on your own computer, which makes this the quickest option to try. For more information, see the Interactive Apps user guide.

## Using VS Code installed on your own computer

If you would rather work in the copy of VS Code on your own machine, two extensions can reach the
cluster:

- **Remote-SSH:** creates a "VS Code **server**" on the cluster. Workspace extensions can then run on the remote machine and directly access its filesystem, shell, compilers, Python environments, etc.

- **SSH-FS** SSH-FS has no server on the cluster; it only accesses files over SFTP. Your programs and extensions run on your local machine. Some extensions support this virtual filesystem, but Claude Code and Codex do not reliably support SSH-FS workspaces.

For example, if you want to work with Claude Code's extension with your files on the cluster, Claude Code runs wherever the **VS Code server is running**, i.e., on your local machine when using SSH-FS and on the cluster with Remote-SSH.

### Do not use Remote-SSH on login nodes

Login nodes are **shared resources among all users** working with the cluster. As discussed earlier, the Remote-SSH extension puts a server on the cluster (here the login node) and spawns many processes. This extension, does not reliably terminate all the processes it starts and therefore you may unknowingly create tens of leftover processes that you are not even aware of. Besides slowing down this node for all the other users, you may exceed the maximum number of processes allowed on the login node (which has a hard limit of 64-process, 4 CPU core, and 32 GB memory). In this case, you may get locked out of your account, through a hold that prevents you from logging in at all, including from
the terminal.

Agentic coding tools make this matter worse. A Claude Code or Codex session runs file searches, builds,
and test suites on your behalf, and each of those spawns processes on whichever host the tool is
running on. This can lead to hitting the process limits on login node very quickly and getting you locked out of your account.

To avoid this issue, we recommend two solutions: 
- Using **SSH-FS** on a login node
because it puts *almost* no load on the system
- Using **Remote-SSH** *a compute node*, which is discussed below in detail.

## SSH-FS to a login node

As discussed earlier, the SSH-FS extension mounts a cluster directory as a folder in VS Code and moves files over SFTP.
Nothing is installed on the cluster and no node is reserved. You can use this to edit your scripts. Then, you can use the **SSH-FS terminal** feature to connect to the cluster. Note that by default, you are on a login node in the terminal, and the commands you enter are executed on the login node. Starting a Python session, installing packages, or running an analysis there can exceed the login node process limits again.

Because SSH-FS does not start a server on the cluster, the Claude Code and Codex extensions do not run through SSH-FS. Alternatively, you can use the **SSH-FS** terminal to use these agents' CLIs. Please request an interactive node and run your agent's on a compute node.

## Remote-SSH to a compute node

A compute node on CARC does not accept connections from outside the cluster, and you can only access it once you have at least one job running on it. Therefore, to connect to them via Remote-SSH extension, we need to follow a four-step process:

**1. Submitting a job that holds the node.** We need to submit a job to the cluster so that Slurm keeps the node allocated to you while you use it:

```bash
sbatch --job-name=vscode --partition=main \
       --nodes=1 --ntasks=1 --cpus-per-task=4 --mem=12G --time=8:00:00 \
       --wrap="sleep infinity"
```
here, you can change the partition, number of cpu cores, amount of memory, request time, or add GPUs by changing this line.

After submitting this command, Slurm responds with the job ID, for example `Submitted batch job 4822945`. 

The resources requested here are the ones VS Code and everything you run inside it are limited to. The job ends by itself after the time requested, here 8 hours.

**2. Picking up the node name.** The queue is checked with:

```bash
squeue --me
```

The job remains pending until Slurm places it. Once the state
is `R`, the `NODELIST(REASON)` column shows the name of the node, for example `d17-03`.

**3. Creating the SSH configuration.** 
Since the compute node is reached through the login node, we need to use the login node as the jump server. Open the file in the `~/.ssh/config` on your own computer and create this section:

```
Host discovery.usc.edu
  HostName discovery.usc.edu
  User <USC NetID>
  IdentityFile ~/.ssh/id_rsa
  ServerAliveInterval 300
  ServerAliveCountMax 2

Host discovery-vscode
  Hostname <nodelist>.hpc.usc.edu
  User <USC NetID>
  ProxyJump discovery.usc.edu
  IdentityFile ~/.ssh/id_rsa
  ServerAliveInterval 300
  ServerAliveCountMax 2
```
In this block:
- Replace `<USC NetID>` with your USC NetID without `@usc.edu`
- Replace `<Nodelist>` with the address you received in Step 2 (for example, `d17-03`).
- To simplify the process, copy the content of the `~/.ssh/id_rsa.pub` **from your own computer** to `~/.ssh/authorized_keys` on the **cluster**.

`ProxyJump` opens the connection to `discovery.usc.edu` first,
then tunnels the connection to the compute node through it.

**4. The connection from VS Code.** The host appears in VS Code as soon as the file is saved. It is opened from the command palette, under **Remote-SSH: Connect to Host**, where `discovery-vscode`
is listed. The first connection takes several minutes while VS Code installs its server into your home directory. Later connections are fast.

Before connecting for the first time, we need to change one VS Code setting. Open the command palette (center top), select **Preferences: Open User Settings (JSON)**, and add these two lines right after the opening `{`, each ending with a comma so that they sit above the settings you already have:

```json
{
    "remote.SSH.enableDynamicForwarding": false,
    "remote.SSH.connectTimeout": 60,
    // ... your other settings
}
```

By default, VS Code opens a SOCKS proxy on your own computer to reach the server it installed on the compute node. When that proxy does not come up, the connection stops at "Waiting for port forwarding to be ready" and stays there without ever reporting an error. Setting `enableDynamicForwarding` to `false` uses a plain port forward instead. Note that both settings apply to every host, so you only do this once, no matter how many sessions you create later.

<div style="border: 2px solid #535353; padding: 5px; border-radius: 5px; background-color: #f9f9f9;">
  Slurm gives you a different node every time you submit a new job. This means that steps 1 to 3 are repeated at the start of each session, and the `Hostname` line of the `discovery-vscode` entry is the one that changes.
</div>


## Setting up the Remote-SSH to a compute node with a script
 
The three steps above are identical every session, so they can be automated. The `vscode-node.sh` script submits the job, waits for Slurm to place it, and writes the SSH configuration for the node it landed on. It also reuses a session you already have rather than submitting a second job.
 
Note that the snippet is modified based on a script recommended by a user.
 
 
Save `vscode-node.sh` in a directory on your `PATH` (for example `~/bin`) and make it executable:
 
```bash
chmod +x ~/bin/vscode-node.sh
```
 
Open the script and edit the settings block at the top:
 
```bash
USC_NetID="ttrojan"                # <-- your USC NetID
LOGIN_HOST="discovery1.usc.edu"    # discovery2.usc.edu, endeavour.usc.edu, ...
NODE_SUFFIX=".hpc.usc.edu"         # compute nodes resolve as <node>.hpc.usc.edu
SBATCH_OPTS="--partition=main --cpus-per-task=4 --mem=12G --time=24:00:00"
                                   # add --account=<project> if you have several
KEY=""                             # SSH key; blank = id_ed25519, id_rsa or id_ecdsa, whichever exists
```
 
Most users only need to change `USC_NetID`. Set `LOGIN_HOST` to the login node for the cluster you work on. The name that appears in your VS Code host list is derived from it, so `discovery1.usc.edu` gives you a host named `discovery1` and `endeavour.usc.edu` gives you one named `endeavour`. `SBATCH_OPTS` holds the resources of every session you start, written the same way you would give them to `sbatch`. If you have more than one project account, add `--account=<project ID>` to this line. Enter `myaccount` on the cluster to see your accounts.
 
Next, install your SSH key on the cluster:
 
```bash
vscode-node.sh setup
```
 
The `setup` command uses a key you already have (`id_ed25519`, `id_rsa`, or `id_ecdsa`) and
generates one only if you have none. It appends the public key to `~/.ssh/authorized_keys` on the
cluster, leaving any keys already there in place, which is the key requirement described in step 3
above.
 
Finally, if you have not set `remote.SSH.enableDynamicForwarding` to `false` in step 4 above, do it now. It applies to every host, so it covers the sessions the script creates as well.
 
### Starting a session
 
Run the script with no arguments:
 
```bash
vscode-node.sh
```
 
If you already have a session, the script reuses it. Otherwise it submits a job, waits for Slurm to allocate a node, and writes the SSH configuration for that node to `~/.ssh/discovery1.conf`. It
also adds a single `Include` line to your `~/.ssh/config` the first time it runs, so your existing configuration is left untouched.
 
The host is opened from the command palette in the same way, under **Remote-SSH: Connect to Host**, where it is listed as `discovery1`.
 
### Resource requests
 
The defaults reserve 4 CPUs and 12 GB of memory for 24 hours on the `main` partition. To change
them for every session, edit `SBATCH_OPTS` in the settings block. To change them for one session, pass the `sbatch` flags on the command line:
 
```bash
vscode-node.sh --partition=debug --time=1:00:00
```
 
The flags from the command line are placed after `SBATCH_OPTS`, and Slurm keeps the later value of a repeated option, so they override the defaults. Use the `--flag=value` form, since a flag with a separate value (`-p debug`) is not recognized. Note that the flags only matter when a new job is submitted. If a session with the same name already exists, the script reuses it and ignores the flags. To change the resources of a running session, stop it first, or start a second session with a different name as described below.
 
Partition run time limits still apply. The `main`, `epyc-64`, and `gpu` partitions allow a maximum
of 48 hours, and the `debug` partition allows 1 hour. For a full list of limits, see the Running Jobs user guide.
 
### Multiple sessions
 
Every session has a name, and the session started with no arguments is the default one. To run a second session alongside it, give it a name, followed by the resources it should have:
 
```bash
vscode-node.sh gpu --partition=gpu --gres=gpu:1
```
 
This session appears in VS Code as `discovery1-gpu`, and its job is named `vscode-gpu` in the queue. Running the same command again reuses that session instead of submitting a second job, so reservations do not accumulate as long as you keep the same names. Each name is a separate reservation, which is the reason to stop a session once you are done with it. VS Code asks for the platform of a host it has not seen before. Answer Linux, and it remembers the answer for that session. 
### Monitoring and stopping sessions
 
To see your sessions, the nodes they are on, and their remaining run time:
 
```bash
vscode-node.sh status
```
 
To cancel:
 
```bash
vscode-node.sh stop          # cancel the default session
vscode-node.sh stop gpu      # cancel the session named gpu
vscode-node.sh stop all      # cancel every session
```
 
### Notes for Windows users
 
The script requires Bash, so run it under Windows Subsystem for Linux or Git Bash. It writes to
the `~/.ssh/config` belonging to the environment it runs in, which is not the same file as your
Windows `%USERPROFILE%\.ssh\config`. Either run VS Code from inside WSL, or point the Remote-SSH
extension at the correct file with the `remote.SSH.configFile` setting.
