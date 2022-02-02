from pathlib import Path
import click

from brownie import Vault, Token, BeefMaster, YakAttack, StrategyLib, accounts, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
acct = accounts.add('')
beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)
yak = YakAttack.at('0x6c545467fC1670e82b9B56A91f48C032537B8bF2')
usdc = Token.at('0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664')
new = YakAttack.at('0x1BDC3587F066b2E2453E3Bc484A06e8DbF368289')

param = { 'from': acct, 'gas_price': gas_strategy }

def main():
    print(f"You are using the '{network.show_active()}' network")
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    dev = acct
    print(f"You are using: 'dev' [{dev.address}]")

    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Strategy balance: ',  yak.estimatedTotalAssets())
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))

    vault.migrateStrategy(yak, new, param)

    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Old Strategy balance: ', yak.estimatedTotalAssets())
    print('new Strategy balance: ', new.estimatedTotalAssets())
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))

    