from pathlib import Path
import yaml
import click

from brownie import Token, Vault, Registry, accounts, network, web3
from brownie.network.gas.strategies import GasNowScalingStrategy
from eth_utils import is_checksum_address
from semantic_version import Version


DEFAULT_VAULT_NAME = lambda token: f"{token.symbol()} yVault"
DEFAULT_VAULT_SYMBOL = lambda token: f"yv{token.symbol()}"

# create a random account that will deploy the vault
# acct = accounts.add();
acct = accounts.add('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80')
gas_price = 103628712501
#gas_price = GasNowScalingStrategy()

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
    
   
    #deploy Registry contract
    reg = Registry.deploy( { 'from': dev, 'gas_price': gas_price})
    registry = Registry.at(reg.address)
    click.echo(f"Registry Deployed at [{reg.address}]")
    #registry.newRelease()

    #registry = Registry.at(
    #    get_address("Vault Registry", default="v2.registry.ychad.eth")
    #)
    
    
    use_proxy = False  # NOTE: Use a proxy to save on gas for experimental Vaults
    
    if click.confirm("Deploy a Proxy Vault", default="Y"):
            use_proxy = True
    
    token = Token.at(get_address("ERC20 Token"))

    if use_proxy:
        gov_default = (
            "0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7"  # strategist msig, no ENS
        )
    else:
        gov_default = "ychad.eth"
    gov = get_address("Yearn Governance", default=gov_default)

    rewards = get_address("Rewards contract", default="treasury.ychad.eth")
    guardian = gov
    if use_proxy == False:
        guardian = get_address("Vault Guardian", default="dev.ychad.eth")
    management = get_address("Vault Management", default="ychad.eth")
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
            
            txn_receipt = registry.newExperimentalVault(*args, {"from": dev, "gas_price": gas_price})
            click.echo(txn_receipt.error())
            vault = Vault.at(txn_receipt.events["NewExperimentalVault"]["vault"])
            click.echo(f"Experimental Vault deployed [{vault.address}]")
            click.echo("    NOTE: Vault is not registered in Registry!")
        else:
            args.append(guardian)
            args.append(management)
            vault = Vault.deploy({ 'from': dev, 'gas_price': gas_price })
            #vault = dev.deploy(Vault,{"gas_price": gas_price})
    
            vault.initialize(*args, { 'from': dev, 'gas_price': gas_price })
            click.echo(f"New Vault Release deployed [{vault.address}]")
            click.echo(
                "    NOTE: Vault is not registered in Registry, please register!"
            )
