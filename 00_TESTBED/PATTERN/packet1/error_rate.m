pyLLR = readmatrix("pythonLLR.txt");
pyHardbit = zeros(1, length(pyLLR));
for i = 1:length(pyLLR)
    if pyLLR(i) > 0
        pyHardbit(i) = 0;
    else
        pyHardbit(i) = 1;
    end
end

hardBit = readmatrix("SNR10dB_hb.dat");

err = 0;

for i = 1:length(pyLLR)
    if pyHardbit(i) ~= hardBit(i)
        err = err + 1;
    end
end

writematrix(pyHardbit, "pyHardbit.txt");

err_rate = err / length(pyLLR)