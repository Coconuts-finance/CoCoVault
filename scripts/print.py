from pathlib import Path
import click

from brownie import Vault, BeefMaster, YakAttack, PTPLifez, StrategyLib, accounts, Token, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy

#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
lib = StrategyLib.at('0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d')
acct = accounts.add('')
beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
beef = BeefMaster.at('0x19284d07aab8Fa6B8C9B29F9Bc3f101b2ad5f661')
yakFarm = '0xf5Ac502C3662c07489662dE5f0e127799D715E1E'
usdc = Token.at('0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664')
yak = YakAttack.at('0x863a69EE19A983f16b06c97c2559fE63628B4EAf')

pp = PTPLifez.at('0xF2FCfB84f46E986fb691Ab35065C6948a3958008')

gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)


param = { 'from': acct, 'gas_price': gas_strategy }


def main():
    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Beef Strategy usdc balance: ', usdc.balanceOf(beef.address))
    print('Yak Strategy usdc balance: ', usdc.balanceOf(yak.address))
    print('PP Strat usdc balance', usdc.balanceOf(pp.address))
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))