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
acct = accounts.add('privKey')
gas_strategy = LinearScalingStrategy("30 gwei", "50 gwei", 1.1)
param = { 'from': acct, 'gas_price': gas_strategy }

#tokens
usdc = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174'
dai = '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063'
weth = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619'
wbtc = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6'
wmatic = '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270'

registry = Registry.at('0xAa5893679788E1FAE460Ae6A96791a712FDC474F')

### THESE VARIABLES NEED TO BE UPDATED
#Deposit limit for vault
limit = 1000000 # $1m in native token
token = Token.at(usdc)
###THESE VARIABLES NEED TO BE UPDATED

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
    
    click.echo(f"You are using: 'dev' [{dev.address}]")
    
    use_proxy = False  # NOTE: Use a proxy to save on gas for experimental Vaults
    
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

        if use_proxy:
            # NOTE: Must always include guardian, even if default
            args.insert(2, guardian)
            txn_receipt = registry.newExperimentalVault(*args, param)
            click.echo(txn_receipt.error())
            vault = Vault.at(txn_receipt.events["NewExperimentalVault"]["vault"])
            click.echo(f"Experimental Vault deployed [{vault.address}]")
            click.echo("    NOTE: Vault is not registered in Registry!")
        else:
            args.append(guardian)
            args.append(management)
            vault = Vault.deploy( param )
        
            click.echo('Vault Deployed')

            vault.initialize(*args, param )
            click.echo(f"New Vault Release deployed [{vault.address}]")
        
            vault.setDepositLimit(limit, param)
            click.echo(f"Deposit limit sent to: [{limit}]")
        


