# CBC-Balistics-with-CC-Tweaked
A simple balistics calculator for CBC using CC: Tweaked. The main balistics calculation was from Malex21

# How to use

There are 3 Computers;
1. The main controler
2. Cannon yaw controler
3. Cannon pitch controler

the main controller will have 2 wireless modems(sides configurable in the code), and each of the Cannon controllers will be adjacent or wired to the Sequenced gearshift.

the code is plug and play made but, the sides and the computer ID will have to be configured.
(The computer ID can be found by typing 'lua' and then 'getComputerID()')

# Note

connecting the gearshift directly to the CBC cannon mount will only spin it 1/8 the required amount, so step it up 1:8 to get the required rotation.

for example to from 32 rpm, step it upto 256 rpm using gears and not the rotation speed controller(because the rotation speed controller will ignore direction)
