% =========================================================================
% Comparator Noise Analysis using Ramp Test & S-Curve Fitting
% =========================================================================
clear; close all; clc;

%% 1. 参数设置 (根据您的仿真 TB 修改)
% -------------------------------------------------------------------------
filename = 'noise_data.csv'; % 导出的 CSV 文件名
T_clk    = 10e-9;            % 时钟周期 (10ns)
T_start  = 100e-9;           % 忽略前 100ns (复位时间)
T_end    = 10.1e-6;          % 扫描结束时间
Sample_Offset = 0.5e-9;      % 在时钟上升沿后 0.5ns 处采样 (Latch 稳定点)
Bin_Width_uV  = 5;           % 直方图统计的电压区间宽度 (单位 uV)

% 逻辑阈值 (用于将模拟 Vout 转为数字 0/1)
V_logic_th = 0.9;            % 例如电源电压的一半

%% 2. 读取数据
% -------------------------------------------------------------------------
fprintf('正在读取 CSV 文件...\n');
% 假设 CSV 格式为: time, Vin, Vout (如果是 time, Vin, time, Vout 也能处理)
data = readmatrix(filename); 

% 自动识别列 (简单判断：通常第1列是时间)
time_vec = data(:,1);
% 假设第2列是 Vin, 第3列是 Vout (如果格式不同，请手动修改列号)
% 注意：如果 Cadence 导出的 CSV 是双时间轴 (4列)，这里需要修改
if size(data, 2) >= 3
    vin_vec  = data(:,2);
    vout_vec = data(:,3); % 或者是第4列，取决于导出设置
    % 如果是双时间轴 (time1, vin, time2, vout)，请取消下面注释并修改
    % time_vec_out = data(:,3); 
    % vout_vec = data(:,4);
else
    error('CSV 数据列数不足，请检查导出格式。');
end

%% 3. 数据重采样 (Soft Resampling)
% -------------------------------------------------------------------------
fprintf('正在重采样数据...\n');

% 生成采样时间点序列 (理想时钟沿 + 偏移)
sample_times = (T_start + Sample_Offset) : T_clk : T_end;

% 使用线性插值提取采样点的 Vin 和 Vout
vin_sampled  = interp1(time_vec, vin_vec,  sample_times, 'linear');
vout_sampled = interp1(time_vec, vout_vec, sample_times, 'linear'); 
% 如果 Vout 有独立时间轴，把上面的 time_vec 换成 time_vec_out

% 数字化 Vout (模拟电平 -> 0/1)
dout_sampled = vout_sampled > V_logic_th;

%% 4. 直方图统计 (Binning)
% -------------------------------------------------------------------------
fprintf('正在进行分箱统计...\n');

% 将电压单位转为 uV 方便处理
vin_uV = vin_sampled * 1e6;

min_v = min(vin_uV);
max_v = max(vin_uV);
edges = min_v : Bin_Width_uV : max_v; % Bin 的边缘
bin_centers = edges(1:end-1) + Bin_Width_uV/2; % Bin 的中心

% 统计每个 Bin 内的概率
num_bins = length(bin_centers);
probs = zeros(1, num_bins);
valid_bins = false(1, num_bins); % 标记有效 Bin (防止空 Bin)

for k = 1:num_bins
    % 找到落在当前 Bin 范围内的索引
    idx = find(vin_uV >= edges(k) & vin_uV < edges(k+1));
    
    if ~isempty(idx)
        % 计算该 Bin 内输出为 1 的比例
        probs(k) = mean(dout_sampled(idx));
        valid_bins(k) = true;
    end
end

% 只保留有效数据
x_data = bin_centers(valid_bins);
y_data = probs(valid_bins);

%% 5. S 曲线拟合 (CDF Fitting)
% -------------------------------------------------------------------------
fprintf('正在拟合高斯 CDF...\n');

% 定义高斯 CDF 模型: p = 0.5 * (1 + erf((x - mu) / (sigma * sqrt(2))))
% MATLAB 的 fit 函数通常用 fittype
ft = fittype('0.5 * (1 + erf((x - mu) / (sigma * sqrt(2))))', ...
             'independent', 'x', 'dependent', 'y');

% 初始猜测 (Start Points)
mu_guess    = mean(x_data); % 猜中心在数据中间
sigma_guess = 30;           % 猜噪声是 30uV
opts = fitoptions(ft);
opts.StartPoint = [mu_guess, sigma_guess];
opts.Lower      = [-Inf, 0]; % sigma 必须大于 0

% 执行拟合
[fit_result, gof] = fit(x_data(:), y_data(:), ft, opts);

% 提取结果
offset_fit = fit_result.mu;
sigma_fit  = fit_result.sigma;

%% 6. 绘图与报告
% -------------------------------------------------------------------------
figure('Color', 'w', 'Name', 'Comparator Noise Analysis');

% 绘制原始数据点
plot(x_data, y_data, 'ko', 'MarkerFaceColor', 'b', 'MarkerSize', 6); hold on;

% 绘制拟合曲线
x_fit = linspace(min(x_data), max(x_data), 1000);
y_fit = feval(fit_result, x_fit);
plot(x_fit, y_fit, 'r-', 'LineWidth', 2);

% 标注辅助线 (16% 和 84%)
y_low = 0.1587; x_low = offset_fit - sigma_fit;
y_high = 0.8413; x_high = offset_fit + sigma_fit;

plot([min(x_fit), x_low, x_low], [y_low, y_low, 0], 'g--');
plot([min(x_fit), x_high, x_high], [y_high, y_high, 0], 'g--');

% 标注文字
title('Comparator Input-Referred Noise (S-Curve)');
xlabel('Input Voltage (\muV)');
ylabel('Probability of Output "1"');
grid on;
legend('Simulation Data', sprintf('CDF Fit (\\sigma=%.2f \\muV)', sigma_fit), 'Location', 'best');

% 打印结果到命令窗口
fprintf('\n================ 结果报告 ================\n');
fprintf('拟合优度 (R-square): %.4f\n', gof.rsquare);
fprintf('------------------------------------------\n');
fprintf('失调电压 (Offset)  : %.2f uV\n', offset_fit);
fprintf('输入噪声 (Sigma)   : %.2f uV (RMS)\n', sigma_fit);
fprintf('==========================================\n');