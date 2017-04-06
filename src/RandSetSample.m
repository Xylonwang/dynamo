function u_list = RandSetSample(cell_of_RandProcess, t, n_samples, opt)
% RANDSETSAMPLE Draws the specified number of samples from a group of RandProcess objects 
% 
% Produces a row vector for each sample set
%
% Note: no probability returned, since this is a pure monte carlo sample

% HISTORY
% ver     date    time       who     changes made
% ---  ---------- -----  ----------- ---------------------------------------
%   2  2017-04-06 00:05  BryanP      Adjusted order of calls to sample
%   1  2016-10-27 14:05  BryanP      Initial Code

if nargin < 3 || isempty(n_samples)
    n_samples = 1;
end

if nargin < 4
    opt = [];
end


% Note: not preallocating b/c not sure of type
u_list = [];
for idx = 1:length(cell_of_RandProcess)
    u_list = [u_list, cell_of_RandProcess{idx}.sample(n_samples, t, opt)]; %#ok<AGROW>
end