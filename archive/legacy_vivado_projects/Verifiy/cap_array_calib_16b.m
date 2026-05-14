% cap_array_calib_16b.m
% =========================================================================
% 分段电容阵列设计工具 (16-bit 校正专用版)
% 
% 核心功能更新：
% 1. 针对 16位 目标分辨率进行权重归一化；
% 2. 输出每一位的“校正系数” (相对于最小 LSB 的倍数)；
% 3. 对比理想二进制权重，评估冗余覆盖范围。
% =========================================================================

clear; close all; clc;
format compact;

%% ================= 1. 全局配置 =================
% --- 目标规格 ---
cfg.target.bits            = 16;    % 目标分辨率
cfg.target.Vref            = 3.3;   % 参考电压

% --- 工艺参数 ---
cfg.process.C_unit_fF      = 8.0;   
cfg.process.C_para_node_r  = 0.05;  % 寄生电容比例
cfg.process.C_comp_fF      = 5.0;   % 比较器输入电容

% --- 良率判定标准 ---
cfg.check.ignore_lsb_bits  = 6;     % 忽略 Seg 1 (LSB段) 的微小误差
cfg.check.noise_tol_lsb    = 0.5;   % 容忍缺口 (以 16-bit LSB 为单位)

% --- Monte Carlo 配置 ---
cfg.mc.enable              = true;  
cfg.mc.runs                = 1000;  
cfg.mc.sigma_unit_pct      = 1.2;   
cfg.mc.sigma_cp_pct        = 2.0;   
cfg.mc.sigma_ccomp_pct     = 2.0;   

% --- 拓扑结构 (总物理位数需 > 16 以提供冗余) ---
% 当前配置: 6+4+5+5 = 20 bits 物理电容
cfg.topo.seg_ratios = {
    [1 2 4 8 16 32],       % Seg 1 (6 bit)
    [2 4 8 16],            % Seg 2 (4 bit)
    [2 2 4 8 16],          % Seg 3 (5 bit)
    [8 8 16 32 64]         % Seg 4 (5 bit)
};
cfg.topo.bridge_init = [4; 4; 12]; % 桥接电容值 (单位: Cu)

%% ================= 2. 设计初始化 =================
[C_nom_ratios, seg_indices, Ncap, Nseg] = parse_topology(cfg.topo.seg_ratios);
fF2F = 1e-15;

% 物理值计算
C_nom_phys   = C_nom_ratios * cfg.process.C_unit_fF * fF2F;
Cp_node_phys = cfg.process.C_unit_fF * cfg.process.C_para_node_r * fF2F;
C_comp_phys  = cfg.process.C_comp_fF * fF2F;

% 理想 16-bit LSB 计算
V_lsb_ideal_16 = cfg.target.Vref / 2^cfg.target.bits;

fprintf('=== 设计概览 (16-bit 校正版) ===\n');
fprintf('  物理总位数: %d bits (含冗余)\n', Ncap);
fprintf('  目标分辨率: %d bits\n', cfg.target.bits);
fprintf('  理想 1 LSB: %.2f uV\n', V_lsb_ideal_16*1e6);

%% ================= 3. 标称权重与校正系数计算 =================
best_bridge = cfg.topo.bridge_init;
Cb_best_phys = best_bridge * cfg.process.C_unit_fF * fF2F;

% 求解电路，得到每一位的实际权重电压 (Weights)
[w_best, V_full_scale] = solve_circuit(C_nom_phys, seg_indices, Cb_best_phys, Nseg, Cp_node_phys, C_comp_phys, cfg.target.Vref);

% --- 关键计算：校正系数 ---
% 1. 相对于物理 LSB (Bit 1) 的倍数 -> 用于数字校正逻辑
cal_coeffs_phys = w_best ./ w_best(1);

% 2. 相对于理想 16-bit LSB 的倍数 -> 用于评估动态范围
weights_in_16b_lsb = w_best ./ V_lsb_ideal_16;

% 3. 实际等效分辨率 (Effective Resolution)
% 看最小的物理 LSB 是理想 16位 LSB 的多少倍。如果 < 1，说明颗粒度足够。
lsb_granularity = weights_in_16b_lsb(1);
effective_bits = log2(cfg.target.Vref / w_best(1));

fprintf('\n=== 3.1 权重与校正系数表 (Calibration Data) ===\n');
fprintf('| Bit | Seg | 物理值(Cu)|  电压权重(uV)  | 权重(Ideal 16b LSB) | 校正系数 (x Phy LSB) |\n');
fprintf('|-----|-----|-----------|----------------|---------------------|----------------------|\n');

seg_map = zeros(Ncap,1);
for s=1:Nseg, seg_map(seg_indices{s}) = s; end

for k = 1:Ncap
    fprintf('| %3d |  %d  |   %4d    | %10.2f     |     %10.2f      |     %12.2f     |\n', ...
        k, seg_map(k), C_nom_ratios(k), w_best(k)*1e6, weights_in_16b_lsb(k), cal_coeffs_phys(k));
end
fprintf('|-----|-----|-----------|----------------|---------------------|----------------------|\n');
fprintf('  * Total Range: %.2f%% of Vref\n', (sum(w_best)/cfg.target.Vref)*100);
fprintf('  * Effective Resolution: %.2f bits (物理LSB = %.2f * 理想LSB)\n', effective_bits, lsb_granularity);

if lsb_granularity > 1.0
    fprintf('⚠️ [警告] 物理 LSB 大于理想 16位 LSB，由于量化误差可能无法达到真 16位精度！建议减小单位电容或调整分段。\n');
else
    fprintf('✅ [通过] 物理 LSB 小于理想 16位 LSB，量化精度满足要求。\n');
end

%% ================= 4. 冗余分析 (Redundancy Check) =================
% 这里的检查基于 16位 LSB 的容限
noise_tol_voltage = V_lsb_ideal_16 * cfg.check.noise_tol_lsb;
[margins, ~, has_missing_nom] = analyze_redundancy(w_best, cfg.check.ignore_lsb_bits, noise_tol_voltage);

min_margin = min(margins(cfg.check.ignore_lsb_bits+1:end));
fprintf('\n=== 3.2 标称冗余检查 ===\n');
fprintf('  关键位最小重叠 (Margin): %.2f uV (%.2f LSBs)\n', min_margin*1e6, min_margin/V_lsb_ideal_16);

%% ================= 5. Monte Carlo 仿真 =================
if cfg.mc.enable
    fprintf('\n=== 4. Monte Carlo 良率分析 (N=%d) ===\n', cfg.mc.runs);
    
    sigma_unit_real  = cfg.mc.sigma_unit_pct / 100;
    
    fail_flags = zeros(cfg.mc.runs, 1);
    min_margin_history = zeros(cfg.mc.runs, 1);
    
    t_start = tic;
    
    for run = 1:cfg.mc.runs
        % 失配模型
        sigma_C = sigma_unit_real ./ sqrt(C_nom_ratios);
        C_mc = C_nom_phys .* (1 + sigma_C .* randn(size(C_nom_phys)));
        
        sigma_Cb = sigma_unit_real ./ sqrt(best_bridge);
        Cb_mc = Cb_best_phys .* (1 + sigma_Cb .* randn(size(best_bridge)));
        
        Cp_mc = Cp_node_phys * (1 + 0.02 * randn());
        C_comp_mc = C_comp_phys * (1 + 0.02 * randn());
        
        % 求解
        [w_mc, ~] = solve_circuit(C_mc, seg_indices, Cb_mc, Nseg, Cp_mc, C_comp_mc, cfg.target.Vref);
        
        % 检查
        [margins_mc, ~, has_missing] = analyze_redundancy(w_mc, cfg.check.ignore_lsb_bits, noise_tol_voltage);
        
        min_margin_history(run) = min(margins_mc(cfg.check.ignore_lsb_bits+1:end));
        fail_flags(run) = has_missing;
    end
    t_end = toc(t_start);
    
    yield_rate = (cfg.mc.runs - sum(fail_flags)) / cfg.mc.runs * 100;
    fprintf('  耗时: %.2f s, 良率: %.2f%%\n', t_end, yield_rate);
    fprintf('  最差 Margin: %.2f uV (%.2f LSBs)\n', min(min_margin_history)*1e6, min(min_margin_history)/V_lsb_ideal_16);
end

%% ================= 6. 可视化报告 (含理想对比) =================
figure('Name','16-bit Calibration Report','Color','w','Position',[100 100 1400 600]);

% 子图1: 权重对比 (Log Scale)
subplot(1,3,1);
semilogy(1:Ncap, w_best/V_lsb_ideal_16, 'b-o', 'LineWidth', 1.5, 'DisplayName', 'Actual Weights');
hold on;
% 绘制理想二进制线 (假设前 Ncap 个位对应理想的低位，或直接画 2^k)
% 这里画一条参考线：2^(k-1) * (Actual_LSB_Weight)
ideal_line = w_best(1)/V_lsb_ideal_16 * 2.^(0:Ncap-1);
semilogy(1:Ncap, ideal_line, 'r--', 'LineWidth', 1, 'DisplayName', 'Binary Slope (Ref)');
yline(2^16, 'g:', '16-bit Full Scale', 'LineWidth', 2);
grid on; legend('Location','NorthWest');
title('Bit Weights vs. 16-bit LSB');
xlabel('Bit Index (1=LSB)'); ylabel('Weight (Normalized to Ideal LSB)');
xlim([1 Ncap]);

% 子图2: 校正系数 (线性)
subplot(1,3,2);
stem(1:Ncap, cal_coeffs_phys, 'filled', 'MarkerFaceColor', [0.2 0.6 0.8]);
grid on;
set(gca, 'YScale', 'log');
title('校正系数 (Calibration Coeffs)');
xlabel('Bit Index'); ylabel('Multiplier (x Actual LSB)');
annotation('textbox', [0.45, 0.8, 0.1, 0.1], 'String', 'Values for Digital Engine', 'FitBoxToText','on');

% 子图3: 冗余覆盖 (Margin)
subplot(1,3,3);
bar(1:Ncap, margins*1e6, 'FaceColor', [0.4 0.7 0.4]);
hold on;
yline(0, 'r-', 'No Overlap');
yline(noise_tol_voltage*1e6, 'm--', 'Noise Limit');
xline(cfg.check.ignore_lsb_bits+0.5, 'k:', 'Ignored LSBs');
title('Bit Overlap / Redundancy');
xlabel('Bit Index'); ylabel('Margin (uV)');
grid on;

%% ================= 7. 核心函数 =================
function [weights, vfull] = solve_circuit(C_vec, seg_idxs, Cb_vec, Nseg, Cp_val, C_comp_val, Vref)
    % 构建电容矩阵并求解节点电压 (保持串行逻辑)
    Cmat = zeros(Nseg);
    for i=1:Nseg
        c_self = sum(C_vec(seg_idxs{i})) + Cp_val;
        if i==Nseg, c_self = c_self + C_comp_val; end
        if i>1, c_self = c_self + Cb_vec(i-1); end
        if i<Nseg, c_self = c_self + Cb_vec(i); end
        Cmat(i,i) = c_self;
    end
    for i=1:Nseg-1
        Cmat(i,i+1) = -Cb_vec(i);
        Cmat(i+1,i) = -Cb_vec(i);
    end
    
    Ncap = numel(C_vec);
    Q = zeros(Nseg, Ncap);
    for k=1:Ncap
        seg_id = 0;
        for s=1:Nseg, if ismember(k,seg_idxs{s}), seg_id=s; break; end; end
        Q(seg_id,k) = C_vec(k)*Vref;
    end
    
    try V_nodes = Cmat \ Q; catch, V_nodes = pinv(Cmat) * Q; end
    weights = V_nodes(Nseg,:)';
    
    % 计算满量程电压
    Q_full = sum(Q,2);
    v_full_vec = Cmat \ Q_full;
    vfull = v_full_vec(Nseg);
end

function [margins, radix, has_missing] = analyze_redundancy(w, ignore_lsb, noise_tol)
    [w_sorted, ~] = sort(w); 
    lsb = w_sorted(1); 
    N = numel(w);
    
    margins = zeros(N,1); 
    sum_lower = 0;
    
    for k=1:N
        margins(k) = (sum_lower + lsb) - w_sorted(k);
        sum_lower = sum_lower + w_sorted(k);
    end
    
    radix = w_sorted(2:end) ./ w_sorted(1:end-1);
    critical_margins = margins(ignore_lsb+1:end);
    has_missing = any(critical_margins < -noise_tol);
end

function [C_ratios, seg_indices, Ncap, Nseg] = parse_topology(seg_ratios_cell)
    Nseg = numel(seg_ratios_cell); 
    C_ratios = []; 
    seg_indices = cell(1,Nseg); 
    idx = 1;
    for s=1:Nseg
        vec = seg_ratios_cell{s}; 
        C_ratios = [C_ratios, vec(:)'];
        len = numel(vec); 
        seg_indices{s} = idx:(idx+len-1); 
        idx = idx+len;
    end
    C_ratios = C_ratios'; Ncap = numel(C_ratios);
end