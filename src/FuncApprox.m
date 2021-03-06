classdef FuncApprox < handle & matlab.mixin.Copyable
%FUNCAPPROX Function approximation abstract class for approx. dynamic programming
%
% Defines an abstract class (defines the strucuture for related
% subclasses) for a Function Approximation for use with approximate dynamic
% programming and other simulations.
%
% originally by Bryan Palmintier 2011

% HISTORY
% ver     date    time       who     changes made
% ---  ---------- -----  ----------- ---------------------------------------
%  14  2017-06-01 22:40  BryanP      reverting incompatible changes and expanding comments to explain 
%  13  2017-06-01 10:15  NicolasG    Update bug fix (python backporting)
%  12  2012-06-04 22:15  BryanP      Added lattice of subplots for 4&5-D
%  11  2012-05-07 22:15  BryanP      (re)build approx before plot if required
%  10  2012-05-07 16:25  BryanP      PLOT: major expansion: 3-D data, plot2D(), level curves
%   9  2012-05-07 12:05  BryanP      Added plot1D() method
%   8  2012-05-07 11:22  BryanP      Added point dimension names property
%   7  2012-04-22 15:25  BryanP      Added ValRange
%   6  2012-03-29 15:15  BryanP      Renamed RawPts to StorePts, Added separate N_RawPts counter
%   5  2012-03-25 22:15  BryanP      Expanded to include core functionality from faThinPlate v1 in superclass
%   4  2012-03-25 15:21  BryanP      Streamlined:
%                                       -- rename access() to approx() to match Curve FItting Toolbox
%                                       -- Remove max(), maxScaledSum(), & step* properties
% 0.3  2011-03-25 18:21  BryanP      Added raw() method
% 0.2  2011-03-24 20:33  BryanP      Implemented a basic copy method
% 0.1  2011-03-17 07:20  BryanP      Initial Version

    properties
        Name = '';          %optional name for identifying the name/usage
        PtDimNames = {};    %optional cell array of names (one item per dimension)
        PlotOpt = struct(...%Structure of plotting options
             'grid_pts', 21 ... %number of grid points per dim for approx in 2-D plots
            ,'line_pts', 101 ... %number of grid points for approximation in 1-D plots
            ,'level_curves', 5 ... %number of level curves to display when plotting in N_Dim-1
            ,'lattice_dims', 5 ... %lattice entries to display (x&y subplot grid)
            ,'show_approx', true ... %option to display (or not) the approximation in plots when possible
            );
    end

    %Read only properties
    properties (SetAccess=protected)
        MinPtDim = 1;
        MaxPtDim = Inf;
        RefreshIsRequired = false;   %Flag: next approx will require rebuilding approximation

        N_RawPts = 0;   %Total number of points used in creating the approximation, maybe larger than N_StorePts
    end

    %Properties to compute on the fly
    properties (Dependent=true, SetAccess=protected)
        N_StorePts; %total number of stored data points. WARNING: includes both stored & new
        N_PtDim;    %number of dimensions for data points
        N_ValDim;   %number of dimensions for data values
        PtRange;    %two row vector of minimum (1,:) and maximum (2,:) extents for points
        ValRange;   %two row vector of minimum (1,:) and maximum (2,:) extents for values
    end

    %Internal (hidden) properies
    properties (Access=protected)
        StorePts;    %set of points for independant variables
        StoreVals;    %corresponding values at each point
        NewPts;         %New points not yet included in the approximation, but will be before next approx
        NewVals;        %Values for NewPts


        Func;    %current approximation, updated as needed
    end

    properties (Access=private)
        %Additional hidden properties to include for Raw
        HiddenRawProps = { 'StorePts', 'StoreVals', 'NewPts', 'NewVals', 'Func'};
    end

    %Abstract hidden methods must be implemented by subclasses
    methods (Abstract, Access = protected)
        % values = do_approx(obj, points)
        %
        % Approximate the value for a given set of inputs (the points).
        % Each state should be a numeric row vector such that a matrix
        % (with one point per row) defines a list of multiple points to
        % approximate. Must return the corresponding values and may also
        % return additional information such as stdev and step sizes
        values = do_approx(obj, points, varargin);

        % build_func(obj)
        %
        % Build/update the function approximation. This is designed for
        % function approximations that maintain an internal represention
        % such as a lookup table, regression, etc. By default, this is only
        % called when new point are added
        build_func(obj, varargin);

    end

    methods
        %======= Constructor =====
        function obj = FuncApprox(pts, vals)
            %Note: A blank constructor is used for special
            %purposes such as reading from *.mat files and copying
            if nargin >= 2 && not(isempty(pts)) && not(isempty(vals))
                obj.update(pts, vals);
            elseif nargin >= 2 && isempty(pts) && isempty(vals)
                %Do nothing, assume we are being called by a sub-class
            elseif nargin > 0
                warning('ADP:FuncApprox:MismatchedInput', ...
                        'Need both points and values (or an empty call). Empty approx created')
            end
        end

        %======= Standard FuncApprox functions =====
        %------------
        %   update
        %------------
        function out_vals = update(obj, pts, vals, varargin)
        % approx_vals = obj.update(points, values)
        %
        % points: one row per input point
        % values: must be a column vector

            if size(pts, 1) ~= size(vals, 1)
                error('ADP:FuncApprox:DimMismatch', ...
                      'Number of data point rows (%d) does not match values (%d)', ...
                      size(pts,1), size(vals,1))
            end
            if isempty(obj.NewPts)
                if  isempty(obj.StorePts)
                    %Note: only check min/max dimensions when creating a new
                    %list. Otherwise it needs to match the existing data
                    if size(pts, 2) > obj.MaxPtDim || size(pts, 2) < obj.MinPtDim
                        if obj.MinPtDim == obj.MaxPtDim
                            dim_limit_string = sprintf('%d', obj.MaxPtDim);
                        else
                            dim_limit_string = sprintf('between %d & %d', obj.MinPtDim, obj.MaxPtDim);
                        end
                        error('ADP:FuncApprox:WrongNumDim', ...
                              '%s approximation requires %s dimensions, you gave %d)', ...
                              class(obj), dim_limit_string, size(pts,2))
                    end

                    %Setup dimensions of StorePts and StoreVals for dimension
                    %checks and easy concatenation
                    obj.StorePts = zeros(0,size(pts,2));
                    obj.StoreVals = zeros(0,size(vals,2));
                    obj.NewPts = zeros(0,size(pts,2));
                    obj.NewVals = zeros(0,size(vals,2));
                end

                if size(pts, 2) ~= obj.N_PtDim
                    error('ADP:FuncApprox:WrongNumDim', ...
                          'Point dimension mismatch: you gave %d, need %d', ...
                          size(pts, 2), obj.N_PtDim)
                end
                if size(vals, 2) ~= obj.N_ValDim
                    error('ADP:FuncApprox:WrongNumDim', ...
                          'Point dimension mismatch: you gave %d, need %d', ...
                          size(vals, 2), obj.N_ValDim)

                end
            end

            obj.NewPts = vertcat(obj.NewPts, pts);
            obj.NewVals = vertcat(obj.NewVals, vals);

            obj.RefreshIsRequired = true;

            %Update total point count

            [pts_size_col_1, ~] = size(pts);  % collapses size of remaining cols into ~

            obj.N_RawPts = obj.N_RawPts + pts_size_col_1;
            
            %if resulting values are requested, use approx to find them
            % Note: the approx function should only specify the desired
            % output points
            if nargout > 0
                out_vals = obj.approx(pts);
            end
        end

        %------------
        %   approx
        %------------
        function out_vals = approx(obj, out_pts, varargin)
        % values = obj.approx(pts)
        %
        % pts: one output point per row
        %
        % Note: varargin only provided for compatibility with approximation
        % specific options. In most use cases it will be blank
            if obj.RefreshIsRequired
                if obj.N_RawPts == 0
                    error('ADP:FuncApprox:NoData', 'No data points, add data with update() before calling approx()')
                end
                
                %build_func must be defined by the child class and updates
                %the internal function approximation based on previously
                %stored values. Since the stored values are managed
                %separately, the function itself takes no parameters.
                obj.build_func();
                
                %The following line ensures that NewPts is refreshed before
                %the next update. In many cases a subclass will have
                %already called this fuction as part of build_func, but
                %this ensures we have cleaned up the point and value lists
                %in case it is not otherwise done.
                obj.merge_new_pts();
    
                obj.RefreshIsRequired = false;
            end
            if size(out_pts,2) ~= obj.N_PtDim
                error('ADP:FuncApprox:WrongNumDim', ...
                      'Point dimension mismatch: you gave %d, need %d', ...
                      size(out_pts, 2), obj.N_PtDim)
            end

            out_vals = obj.do_approx(out_pts, varargin{:});
        end

        %----------
        %   plot
        %----------
        function plot(obj, varargin)
            if obj.RefreshIsRequired
                if obj.N_RawPts == 0
                    error('ADP:FuncApprox:NoData', 'No data points, add data with update() before calling approx()')
                end
                obj.build_func()

                obj.RefreshIsRequired = false;
            end

            switch obj.N_PtDim
                case 1
                    obj.plot1D(1, varargin{:})
                case 2
                    obj.plot2D([1,2], [], varargin{:})
                case 3
                    obj.plot2D([1,2], [], varargin{:})
                case 4
                    obj.plotLattice([1,2], [3,4], [], varargin{:})
                case 5
                    obj.plotLattice([1,2], [3,4], [], varargin{:})

                otherwise
                    error('ADP:FuncApprox:NotImplemented', ...
                          'Plot not implemented for > 5 dimensions,\n Try plot1D, plot2D, or plotGrid for selected dimensions')
            end

        end

        %----------
        %   plot1D
        %----------
        function plot1D(obj, dim, varargin)
            range = obj.PtRange;
            use_disc_lvls = false;  %flag if found & using discrete values

            % [1] Plot Approximation
            if obj.PlotOpt.show_approx
                % a) For 2-D data, setup level curves
                if obj.N_PtDim == 2
                    % i> Identify the dimension to vary
                    l_dim = mod(dim+2, 2) +1;

                    % ii> if there are only a few unique levels for the 2nd
                    % dimension, use them, otherwise set up a linear
                    % spacing
                    [levels, ~, lvl_for_pt] = unique(obj.StorePts(:,l_dim));
                    if length(levels) > obj.PlotOpt.level_curves
                        levels = linspace(range(1,l_dim), range(2,l_dim),obj.PlotOpt.level_curves);
                    else
                        use_disc_lvls = true;
                    end

                    % iii> Cover the rainbow across the levels
                    colors = colormap(hsv(length(levels)));
                    set(gcf,'DefaultAxesColorOrder', colors)

                    % iv> identify x values
                    x_approx = linspace(range(1,dim), range(2,dim),obj.PlotOpt.line_pts)';

                    % v> Compute y approximations
                    y_approx = NaN(obj.PlotOpt.line_pts, length(levels));
                    for lv = 1:length(levels)
                        y_approx(:, lv) = obj.approx(...
                            horzcat(x_approx, levels(lv) * ones(obj.PlotOpt.line_pts, 1)), ...
                            varargin{:});
                    end

                % b) Otherwise setup a single line (for 3+ D use the
                % diagonal)
                else
                    % i> Setup approximation space for all dimensions
                    approx_sp = NaN(obj.PlotOpt.grid_pts, obj.N_PtDim);
                    for d = 1:obj.N_PtDim
                        approx_sp(:,d) = linspace(range(1,d), range(2,d),obj.PlotOpt.grid_pts)';
                    end
                    % ii> Extract our x-dimension
                    x_approx = approx_sp(:,dim);

                    % iii> Compute corresponding values
                    y_approx = obj.approx(approx_sp, varargin{:});
                end

                % c) actually plot the lines
                plot(x_approx, y_approx, 'LineWidth', 1)

                % d) and if using level curves, add legend
                if obj.N_PtDim == 2 && length(levels) > 1
                    if not(isempty(obj.PtDimNames))
                        leg_intro = sprintf('%s=',strrep(obj.PtDimNames{l_dim},'_','\_'));
                    else
                        leg_intro = '';
                    end
                    leg_text = arrayfun(@(x) sprintf('%s%g',leg_intro,x), levels, 'UniformOutput',false);
                    legend(leg_text, 'Location', 'Best')
                end
            end

            % [2] Overlay the point cloud
            %   a) handle existing hold state
            old_hold = ishold();
            hold('on')

            %   b) Actually plot the points
            if use_disc_lvls
                %   i> use darkened, matching point colors with discrete levels
                colors = colors * 0.5;
                for lv = 1:length(levels)
                    lvl_map = lvl_for_pt == lv;
                    plot(obj.StorePts(lvl_map, dim), obj.StoreVals(lvl_map,:),'o', 'Color', colors(lv,:))
                end

            else
                %   ii> otherwise raw data points as black dots
                plot(obj.StorePts(:,dim),obj.StoreVals,'ko')
            end

            %	c) return to old hold state
            if not(old_hold)
                hold('off')
            end

            % [3] add axis labels
            %Note: the strrep keeps any _'s from being converted to
            %subscripts in the plot label
            if not(isempty(obj.PtDimNames))
                xlabel(strrep(obj.PtDimNames{dim},'_','\_'))
            end

        end

        %------------
        %   plot2D
        %------------
        function plot2D(obj, dim, other_dim_val, varargin)
            if nargin < 3
                other_dim_val = [];
            end

            range = obj.PtRange;
            use_disc_lvls = false;  %flag if found & using discrete values

            % [1] handle existing hold state
            %   a) Store current state
            old_hold = ishold();
            %   b) Clear figure and reset to default 3-D view
            if not(old_hold)
                clf;
                view(3)
            end
            %   c) We need hold enabled so can see all components of figure
            hold('on')

            % [2] Plot Approximation
            if obj.PlotOpt.show_approx
                % a) Setup baselineapproximation space
                if isempty(other_dim_val)
                    approx_sp = NaN(obj.PlotOpt.grid_pts, obj.N_PtDim);
                    %Note: initially will use the (hyper-)diagonal across all dimensions
                    for d = 1:obj.N_PtDim
                        approx_sp(:,d) = linspace(range(1,d), range(2,d),obj.PlotOpt.grid_pts)';
                    end
                else
                    approx_sp = repmat(other_dim_val,obj.PlotOpt.grid_pts,1);
                    % Prefill first two dimensions,
                    approx_sp(:,dim(1)) = linspace(range(1,dim(1)), range(2,dim(1)),obj.PlotOpt.grid_pts)';
                    approx_sp(:,dim(2)) = linspace(range(1,dim(2)), range(2,dim(2)),obj.PlotOpt.grid_pts)';
                end

                % a) Identify additional dimensions
                other_dim = setdiff(1:obj.N_PtDim, dim);

                % a) Use speficified levels for other dimensions if
                % provided
                if not(isempty(other_dim_val))
                    plot2D_helper(dim, approx_sp, 'Interp', 0.7, 'b')

                    t_str = sprintf('Slice: ');
                    if not(isempty(obj.PtDimNames))
                        for idx = 1:length(other_dim)
                            t_str = [t_str, sprintf('%s=%g ', ...
                                strrep(obj.PtDimNames{other_dim(idx)},'_','\_'), ...
                                other_dim_val(other_dim(idx)))]; %#ok<AGROW>
                        end
                    end
                    title(t_str);

                % b) For other 3-D data, create level surfaces
                elseif obj.N_PtDim == 3
                    % ii> if there are only a few unique levels for the
                    % extra dimension, use them, otherwise set up a linear
                    % spacing
                    [levels, ~, lvl_for_pt] = unique(obj.StorePts(:,other_dim));
                    if length(levels) > obj.PlotOpt.level_curves
                        levels = linspace(range(1,other_dim), range(2,other_dim),obj.PlotOpt.level_curves);
                    else
                        use_disc_lvls = true;
                    end

                    % iii> Cover the rainbow across the levels
                    colors = colormap(hsv(length(levels)));

                    % iv> Loop over values for the level dimension
                    for lv = 1:length(levels)
                        level_sp = approx_sp;
                        level_sp(:, other_dim) = levels(lv);
                        plot2D_helper(dim, level_sp, colors(lv,:), 0.5, 'k')
                    end

                    % v> Add legend
                    if not(isempty(obj.PtDimNames))
                        leg_intro = sprintf('%s=',strrep(obj.PtDimNames{other_dim},'_','\_'));
                    else
                        leg_intro = '';
                    end
                    leg_text = arrayfun(@(x) sprintf('%s%g',leg_intro,x), levels, 'UniformOutput',false);
                    legend(leg_text, 'Location', 'BestOutside')


                % c) Otherwise setup a single surface (for 4+D this uses the
                % diagonal)
                else
                    plot2D_helper(dim, approx_sp, 'Interp', 0.7, 'k')
                    title('Hyperdiagonal for other dimensions')
                end

            end

            %PLOT2D_HELPER: Internal helper function to abstract out
            %surface creation
            function plot2D_helper(dim, approx_in, face_color, trans, line_color)
                z_approx = NaN(obj.PlotOpt.grid_pts, obj.PlotOpt.grid_pts);

                % Creat local copy of the approximation space
                approx_temp = approx_in;

                %Compute approximation by looping over y and
                %vectorizing x
                % Note: for >1-D this will use the (hyper-)diagonal across
                % other dimensions
                for y_idx = 1:obj.PlotOpt.grid_pts;
                    % Replace the Y axis column with the corresponding Y data
                    % for this y_index from the complete approximation
                    approx_temp(:,dim(2)) = approx_in(y_idx, dim(2));
                    z_approx(y_idx,:) = obj.approx(approx_temp, varargin{:});
                end
                %-- Plot the approximation
                % Note: FaceColor=Interp causes nice smooth color gradients
                surf(approx_in(:,dim(1)),approx_in(:,dim(2)),z_approx, ...
                    'FaceColor', face_color, 'EdgeColor', line_color)

                %make semi-transparent so we can see back-side and
                %hidden points
                alpha(trans)
            end

            % [3] Overlay the point cloud
            if not(isempty(other_dim_val))
                % (A) with specified other dim vals: use black points
                %   1> first identify points to plot
                to_plot = all(bsxfun(@eq, obj.StorePts(:, other_dim),...
                                        other_dim_val(other_dim)),2);
                plot3(obj.StorePts(to_plot,dim(1)),obj.StorePts(to_plot,dim(2)),obj.StoreVals(to_plot,:),'k.')
            elseif use_disc_lvls
                % (B) with discrete levels: use darkened, matching point colors
                colors = colors * 0.5;
                for lv = 1:length(levels)
                    lvl_map = lvl_for_pt == lv;
                    plot3(obj.StorePts(lvl_map,dim(1)),obj.StorePts(lvl_map,dim(2)),...
                        obj.StoreVals(lvl_map,:),'.', 'MarkerEdgeColor', colors(lv,:))
                end

            else
                % (C) otherwise raw data points as black dots
                plot3(obj.StorePts(:,dim(1)),obj.StorePts(:,dim(2)),obj.StoreVals,'k.')
            end

            % [4] add axis labels, etc
            %Note: the strrep keeps any _'s from being converted to
            %subscripts in the plot label
            if not(isempty(obj.PtDimNames))
                xlabel(strrep(obj.PtDimNames{1},'_','\_'))
                ylabel(strrep(obj.PtDimNames{2},'_','\_'))
            end

            grid('on')

            % [5] return to old hold state
            if not(old_hold)
                hold('off')
            end

        end

        %------------
        %   plotLattice
        %------------
        function plotLattice(obj, plot_dims, lat_dims, other_dim_val, varargin)

            % 1) Initialize
            %  A] use middle values for any unspecified dimensions
            if nargin < 4 || isempty(other_dim_val)
                other_dim_val = 0.5 * ones(1, obj.N_PtDim);
            end

            % 2) Setup a lattice of plots
            %  A] Identify X lattice dims
            range = obj.PtRange;

            x_lat = unique(obj.StorePts(:,lat_dims(1)));
            if length(x_lat) > obj.PlotOpt.lattice_dims
                x_lat = linspace(range(1,lat_dims(1)), range(2,lat_dims(1)),obj.PlotOpt.lattice_dims);
            end

            %  B] Identify Y lattice dims
            y_lat = unique(obj.StorePts(:,lat_dims(2)));
            if length(y_lat) > obj.PlotOpt.lattice_dims
                y_lat = linspace(range(1,lat_dims(2)), range(2,lat_dims(2)),obj.PlotOpt.lattice_dims);
            end

            %  C] Setup subplots
            for x_lat_idx = 1:length(x_lat)
                for y_lat_idx = 1:length(y_lat)
                    subplot(length(y_lat),length(x_lat),...
                        (length(y_lat)-y_lat_idx)*length(x_lat) + x_lat_idx)
                    % apply hold & view for each sub-axis
                    hold('on')
                    view(3);

                    vals_for_sub_plot = other_dim_val;
                    vals_for_sub_plot(lat_dims) = [x_lat(x_lat_idx) y_lat(y_lat_idx)];
                    obj.plot2D(plot_dims, vals_for_sub_plot, varargin{:})

                end
            end
        end

        %------------
        %   raw
        %------------
        % Returns the raw value function approximation
        % There is no need to maintain compatibility between versions
        function raw_data = raw(obj)
            % Method: raw Allows read-only access to otherwise hidden
            % properties. Details subject to change.
            warning('FuncApprox:rawMayChange', 'Results of raw subject to change, use for debugging only!')
            raw_data.class = class(obj);

            public_props = properties(obj);
            for p = 1:length(public_props)
                p_name = public_props{p};
                raw_data.(p_name) = obj.(p_name);
            end

            for p = 1:length(obj.HiddenRawProps)
                p_name = obj.HiddenRawProps{p};
                raw_data.(p_name) = obj.(p_name);
            end


        end

        %% ===== Property value maintenance
        function n_points = get.N_StorePts(obj)
            n_points = size(obj.StorePts,1) + size(obj.NewPts,1);
        end

        function n_dim = get.N_PtDim(obj)
            n_dim = size(obj.StorePts,2);
        end

        function n_dim = get.N_ValDim(obj)
            n_dim = size(obj.StoreVals,2);
        end

        function p_range = get.PtRange(obj)
            p_range = NaN(2,obj.N_PtDim);
            if obj.N_StorePts > 0
                % Note, minmax (NeuralNetwork toolbox) is much slower.
                temp = vertcat(obj.StorePts, obj.NewPts);
                p_range = vertcat(min(temp), max(temp));
            end
        end

        function v_range = get.ValRange(obj)
            v_range = NaN(2,obj.N_ValDim);
            if obj.N_StorePts > 0
                % Note, minmax (NeuralNetwork toolbox) is much slower.
                temp = vertcat(obj.StoreVals, obj.NewVals);
                v_range = vertcat(min(temp), max(temp));
            end
        end

    end

    methods(Access = protected)
        function merge_new_pts(obj)
            obj.StorePts = vertcat(obj.StorePts, obj.NewPts);
            obj.StoreVals = vertcat(obj.StoreVals, obj.NewVals);
            obj.NewPts = zeros(0,obj.N_PtDim);
            obj.NewVals = zeros(0,obj.N_ValDim);
        end

    end
end
