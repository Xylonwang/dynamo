classdef RandProcess < AbstractSet
%RANDPROCESS Random Process abstract class for dynamic programming
%
% Defines an abstract class (defines the strucuture for related
% subclasses) for a Random Process for use with dynamic programming and
% other simulations
%
% IMPORTANT: all processes must have a single, starting state for t=1
%
% originally by Bryan Palmintier 2010

% HISTORY
% ver     date    time       who     changes made
% ---  ---------- -----  ----------- ---------------------------------------
%  15  2017-07-14 11:10  BryanP      Refactor generally usable code from rpDiscreteSample to here 
%  14  2017-07-14 06:02  BryanP      Clarify condintional and unconditional use for sample() 
%  13  2017-04-10 16:36  BryanP      Make sample depend on state 
%  12  2017-04-05 23:52  BryanP      Added checkState, various bugfixes
%  11  2017-04-05 22:52  BryanP      include reset() implementation
%  10  2017-04-05 22:02  BryanP      Put t as first parameter for dlistnext
%   9  2017-04-05 15:12  BryanP      Setup for 1-based t indexing and pure value states (no state_n)  
%   8  2016-10-07 01:40  BryanP      Convert as_array to wrapper for dlistnext 
%   7  2016-10-06 11:40  DheepakK    as_array that throws an error
%   6  2016-07-07 09:40  BryanP      Extracted out common pieces to form AbstractSet class
%   5  2010-12-23 19:30  BryanP      Made t an abstract property to allow subclass error handling
%   4  2010-12-15 23:30  BryanP      Added t_max for dlist(... 'all')
%   3  2010-12-14 12:44  BryanP      Added value returns to dlist*
%   2  2010-12-13 21:20  BryanP      distinguish dsim & sim add internal t
%   1  2010-12-13 12:20  BryanP      Initial Version

    % Read only properties
    properties (GetAccess = 'public', SetAccess='protected')
        t = NaN           %current timestep
        cur_state = NaN   %current state
    end
    
    % Internal properties
    properties (Access='protected')
        Values = {};    % cell row vector of values: 1 cell column per time, typically column vectors per time
        Prob = {};      % cell row vector of (unconditional) probabilities for each time period
        UncondCdf = {}; % cell row vector of (unconditional) cumulative distribution for each time period
        
        Tmax = Inf;       % Largest time with specified distribution
    end


    methods (Abstract)
        %% ===== Support for discrete usage
        % These need to be defined even for continuous processes, for
        % compatability with DP.
        %
        % IMPORTANT: all processes must have a single, starting state for
        % t=1

        % DLISTNEXT List next discrete states & probabilities
        %
        % List possible next states (by number) along with conditional
        % probability P(s_{t+1} | s_t)
        %
        % If t is not provided, the current simulation time is assumed
        %
        % If the state is not valid at t, an error with ID
        % 'RandProcess:InvalidState' should be thrown
        %
        % If t is out of the valid range, an error with ID
        % 'RandProcess:InvalidTime'
        [next_state_list, prob] = dlistnext (obj, t, state )
    end

    methods
        function state_list = sample(obj, N, t, ~)
        %SAMPLE draw state samples for the given time and (current) state
        %
        % Usage:
        %   state_list = disc_samp_object.sample()
        %       One sample state from current time, using conditional
        %       probability for current_state
        %   state_list = sample(obj, N)
        %       Return N samples
        %   state_list = sample(obj, N, t)
        %       Specify time and sample based on unconditional probability
        %       across all valid states for t
        %   state_list = sample(obj, N, t, cur_state)
        %       Sample specified time using conditional probability
        %       starting from provided state
            if nargin < 2
                N = 1;
            end
            
            if nargin < 3 || isempty(t)
                t=obj.t;
            end
            
            %Handle any non integer or large values for time
            t = min(floor(t), obj.Tmax);

            idx_at_t = zeros(N,1);
            for samp_idx = 1:N
                idx_at_t(samp_idx) = find(rand(1) <= obj.UncondCdf{t}, 1, 'first');
            end
            state_list = obj.Values{t}(idx_at_t,:);
        end


        function [val, prob] = as_array(obj, varargin)
            %For a RandProcess, as_array is a simple wrapper around
            %dlistnext for the current state and time.c

            [val, prob] = obj.dlistnext(obj.cur_state, obj.t, varargin);
        end

        function reset(obj, initial_state)
            % RESET reset simulation
            %
            % rand_proc_obj.reset()
            %       resets t=1 and a random initial state
            % rand_proc_obj.reset(initial_state)
        
            obj.t = 1;
            if nargin > 1
                %Check state will error out if state is invalid
                obj.checkState(obj.t, initial_state);
                
                obj.cur_state = initial_state;
            else
                obj.cur_state = obj.sample();
            end
        end

        %% ===== Support for discrete usage
        % These need to be defined even for continuous processes, for
        % compatability with DP.

        function state_list = dlist (obj, t)
        % DLIST List possible discrete states
        %
        % List possible discrete states by number for given time
        % if t is not listed, the states for the current simulation time
        % are returned.
        %
        % To get a list of all possible states pass with t='all'
        %
        % Note: probabilities can't be returned, since transition probabilities
        % are in general a function of the current state.
            if nargin < 2 || isempty(t)
                state_list = obj.dlist(obj.t);
            elseif (ischar(t) && strcmp(t, 'all'))
                state_list = unique(cell2mat(obj.Values'),'rows');
            else
                state_list = obj.state_info(t);
            end
        end

        function state_series = dsim(obj, t_list, initial_value) %#ok<INUSD>
        % DSIM Simulate discrete process.
        %
        % A column vector for t is assumed to be a series of times for
        % which to return results. Intermediate times are also computed, if
        % needed, but not returned. The initial value is not returned in
        % the value series. Only one simulation is run, such that out of
        % order times will be sorted before simulation and duplicate times
        % will return the same result
        %
        % Invalid times (t<1) return NaN
        %
        % Note: after calling dsim, the process internal time will be set to
        % the final value of t_list

            %identify valid simulation times
            ok = (t_list >= 1);

            %initialize outputs
            state_series = zeros(size(t_list),obj.N_dim);
            state_series(not(ok),:) = NaN;

            %only simulate valid values of t_list
            t_list = t_list(ok);

            %only run the simulation if there are valid times to simulate.
            %If not, we have already filled the value list with NaNs and
            %can skip ahead to the state list if requested.
            if not(isempty(t_list))
                %Find times we need to sample
                [t_list, ~, sample_map] = unique(t_list);

                %initalize sample results vectors
                v_list = zeros(size(t_list, obj.N_dim));

                %Sample all required times
                for t_idx = 1:length(t_list)
                    v_list = obj.sample(t_list(t_idx));
                end

                %Set the current state
                obj.t = t_list(end);
                obj.cur_state = v_list(end, :);

                %Reorder samples to match the valid input times
                v_list = v_list(sample_map,:);

                %Now Stuff the correct values into the full output list
                state_series(ok,:) = v_list;
            end
        end

        %% ===== General (discrete or continuous) Methods
        function state_series = sim(obj, t_list, initial_state)
        % SIM Simulate process for desired (continuous) times
        %
        % A column vector for t is assumed to be a series of times for
        % which to return results. Intermediate times are also computed, if
        % needed. The initial value is not returned in the value series.
        %
        % Function must handle arbitrary positive values for t_list
        % Invalid times (t<=1) return NaN
        %
        % Note: after calling sim, the process internal time will be set to
        % the final value of t_list
        %
        % Note: This baseline implementation assumes a discrete process and
        % treats accordingly by rounds down to the nearest integer time
        % (zero order hold)
            if nargin < 3
                initial_state = [];
            end
            state_series = obj.dsim(floor(t_list), initial_state);
        end

        function value_range = range(obj, t)
        % RANGE Find value range for given time
        %
        % Returns vector with [min max] value range for specified time
        % if t is not provided, the range for the current simulation time
        % is returned.
        %
        % To get the possible range across all times use t='all'
            if nargin < 2 || isempty(t)
                t= obj.t;
            end

            if ischar(t) && strcmp(t, 'all')
                state_list_to_range = cell2mat(obj.Values');
            else
                %Handle any non-integer or large values
                t = min(floor(t), obj.Tmax);

                if t < 1
                    error('RandProcess:InvalidTime', 'Only t>=1 valid for rpDiscreteSample')
                else
                    state_list_to_range = obj.Values{t};
                end
            end
            value_range = [min(state_list_to_range); max(state_list_to_range)];
        end


        %% ===== Additional simulation support
        function [state, t] = step(obj, delta_t)
        %STEP simulate forward or backward
        %
        % by default steps forward by delta_t = 1
            if nargin < 2
                delta_t = 1;
            end
            %compute the proposed new time
            new_t = obj.t + delta_t;

            %check if it is valid, if not return empty results
            if new_t < 1
                state = [];
                t = obj.t;
                return
            else
                %if new time is valid simulate forward as needed
                if floor(obj.t) == floor(new_t)
                    %No need to actually change, b/c we have discrete steps
                    %that round
                    state = obj.cur_state;
                else
                    t = new_t;
                    state = obj.sample(1, t);

                    % Update our stored state
                    obj.t = t;
                    obj.cur_state = state;

                end

            end

        end
        
        function state_ok = checkState(obj, t, state)
            % CHECKSTATE Check that state is valid for a given time
            %
            % rand_proc_object.checkState(t, state)
            %       Raise 'RandProc:InvalidState' error if t is not valid in time t
            % state_ok = rand_proc_object.checkState(t, state)
            %       No error, simply return true/false if state is
            %       valid/not
            state_ok = not(isempty(state)) && ismember(state, obj.Values{t}, 'rows');
            
            if nargout == 0 && not(state_ok)
                error('RandProcess:InvalidState', 'State %s is not valid at time %d', state, t)
            end
        end

        
    end
    
    methods (Access = protected)
        %% ===== Helper Functions
        function [state_list, prob] = state_info (obj, t )
            % STATE_INFO Helper function to return full set of state
            % information for a given time (for discrete time processes)
            if t < 1
                error('RandProcess:InvalidTime', 'Only t>1 valid for rpDiscreteSample')
            else
                % make sure time is an integer
                t = floor(t);
                
                % and use t=Tmax for any t>Tmax
                t = min(t, obj.Tmax);
                
                %if we get here, we know the time is valid
                state_list = obj.Values{t};
                prob = obj.Prob{t};
            end
        end
        
    end

end
