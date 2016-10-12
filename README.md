# Travel in times: historic journey planner

Scripts for installing the system, written for Ubuntu Server 16.04 LTS.

## Requirements

Written for Ubuntu Server 16.04 LTS.


## Setup

Add this repository to a machine using the following, as your normal username (not root). In the listing the grouped items can usually be cut and pasted together into the command shell, others require responding to a prompt:

```shell
# Install git
# user@machine:~$
sudo apt-get -y install git

# Tell git who you are
# git config --global user.name "Your git username"
# git config --global user.email "Your git email"
# git config --global push.default simple

# Clone the repo
git clone https://github.com/campop/travelintimes.git

# Move it to the right place
sudo mv travelintimes /opt
cd /opt/travelintimes/
git config core.sharedRepository group

# Create a user - without prompting for e.g. office 'phone number
sudo adduser --gecos "" travelintimes

# Create the rollout group
sudo addgroup rollout

# Add your username to the rollout group
sudo adduser `whoami` rollout

# Some command shells won't detect the preceding group change, so reset your shell eg. by logging out and then back in again:
exit

# Login
# user@client:~$
ssh user@machine

# Set ownership and group
# user@machine:~$
sudo chown -R travelintimes.rollout /opt/travelintimes

# Set group permissions and add sticky group bit
sudo chmod -R g+w /opt/travelintimes
sudo find /opt/travelintimes -type d -exec chmod g+s {} \;
```
