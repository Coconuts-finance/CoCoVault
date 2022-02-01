#Deployment script for Vault without a Registry
from pathlib import Path
import yaml
import click

from brownie import Token, Vault, Registry, accounts, network, web3
from brownie.network.gas.strategies import LinearScalingStrategy
from eth_utils import is_checksum_address
from semantic_version import Version


DEFAULT_VAULT_NAME = lambda token: f"{token.symbol()} cVault"
DEFAULT_VAULT_SYMBOL = lambda token: f"cv{token.symbol()}"

#Variables
acct = accounts.add('')
gas_strategy = LinearScalingStrategy("30 gwei", "50 gwei", 1.1)

#Deposit limit for vault
#1M in usdc.e
limit = 1000000000000

param = { 'from': acct, 'gas_price': gas_strategy }

usdce = '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664'

PACKAGE_VERSION = yaml.safe_load(
    (Path(__file__).parent.parent / "ethpm-config.yaml").read_text()
)["version"]


def get_address(msg: str, default: str = None) -> str:
    val = click.prompt(msg, default=default)

    # Keep asking user for click.prompt until it passes
    while True:

        if is_checksum_address(val):
            return val
        elif addr := web3.ens.address(val):
            click.echo(f"Found ENS '{val}' [{addr}]")
            return addr

        click.echo(
            f"I'm sorry, but '{val}' is not a checksummed address or valid ENS record"
        )
        # NOTE: Only display default once
        val = click.prompt(msg)


def main():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = acct
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    
    use_proxy = False  # NOTE: Use a proxy to save on gas for experimental Vaults
    
    token = Token.at(get_address("ERC20 Token"))

    gov = get_address("CNC Governance", default=dev)

    rewards = get_address("Rewards contract", default=dev)
    guardian = gov
    if use_proxy == False:
        guardian = get_address("Vault Guardian", default=dev)
    management = get_address("Vault Management", default=dev)
    name = click.prompt(f"Set description", default=DEFAULT_VAULT_NAME(token))
    symbol = click.prompt(f"Set symbol", default=DEFAULT_VAULT_SYMBOL(token))
    
    click.echo(
        f"""
    Vault Deployment Parameters

         use proxy: {use_proxy}
     token address: {token.address}
      token symbol: {DEFAULT_VAULT_SYMBOL(token)}
        governance: {gov}
        management: {management}
           rewards: {rewards}
          guardian: {guardian}
              name: '{name}'
            symbol: '{symbol}'
    """
    )

    if click.confirm("Deploy New Vault"):
        args = [
            token,
            gov,
            rewards,
            # NOTE: Empty string `""` means no override (don't use click default tho)
            name if name != DEFAULT_VAULT_NAME(token) else "",
            symbol if symbol != DEFAULT_VAULT_SYMBOL(token) else "",
        ]
        
        args.append(guardian)
        args.append(management)
        vault = Vault.deploy( param )
        #vault = dev.deploy(Vault,{"gas_price": gas_price})
        click.echo('Vault Deployed')

        init = vault.initialize(*args, param )
        click.echo(f"New Vault Release deployed [{vault.address}]")
        
        vault.setDepositLimit(limit, param)
        click.echo(f"Deposit limit sent to: [{limit}]")


