% MATLAB implementation for Mixture-based Superpixel Segmentation
% (MISP). If you use the code, please cite the following paper:
% 
% Sertac Arisoy and Koray Kayabol, "Mixture-based superpixel 
% segmentation and classification of SAR images", 
% IEEE Geoscience and Remote Sensing Letters, vol.13, no. 11, 
% pp. 1721-1725, 2016.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Copyright (c) 2016, Sertac Arisoy, Koray Kayabol, % 
% <sarisoy@gtu.edu.tr>, <koray.kayabol@gtu.edu.tr>, %             
% All rights reserved                               %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Compute MISP superpixels given a SAR image.
% Input:
%       img - is the greyscale SAR image. 
%       RegionSize - is the starting size of the superpixels. This parameter arranges the
%       superpixel numbers.
%       alfa - is concentration parameter of the mixture proportions (default =1000000)

% Output:
%       sMap - raw superpixel map
%     


function  sMap=misp(img,RegionSize,alfa)

% Assign default alfa value, if it is not set.
if ~exist('alfa','var') | isempty(alfa),   alfa = 1000000;   end


% Since we use Nakagami distribution for similarity, 
% we calculate the amplitude of each pixel. 
s = sqrt(img) + 0.01; %To avoid 0/0 in the calculations, we add a small number


% Padding X with circular boundary
[M,N] = size(s);
NN = M*N;
neig = 0; 
spad = [s(neig:-1:1,neig:-1:1) s(neig:-1:1,:) s(1:neig,N-(neig-1):N)'	
    s(:,neig:-1:1) s s(:,N:-1:N-(neig-1))
    s(M-(neig-1):M,1:neig)' s(M:-1:M-(neig-1),:) s(M-(neig-1):M,N-(neig-1):N)];

%% Find initial superpixel region according to RegionSize 
Ms = ceil(M/RegionSize);
Ns = ceil(N/RegionSize);
Ks = Ms*Ns;
Mp = Ms*RegionSize;
Np = Ns*RegionSize;
k = 0;
sMap = zeros(M,N);
for ms = 1:Ms
    for ns = 1:Ns
        if ms~=Ms && ns~=Ns
            k = k+1;
            [X2 X1] = meshgrid((ms-1)*RegionSize+1:ms*RegionSize,(ns-1)*RegionSize+1:ns*RegionSize);
            x1 = reshape(X1,1,[]); x2 = reshape(X2,1,[]);
            ImSeg(k).index = sub2ind([M N], x2, x1)';
        elseif ms==Ms && ns~=Ns
            k = k+1;
            [X2 X1] = meshgrid((ms-1)*RegionSize+1:M,(ns-1)*RegionSize+1:ns*RegionSize);
            x1 = reshape(X1,1,[]); x2 = reshape(X2,1,[]);
            ImSeg(k).index = sub2ind([M N], x2, x1)';
        elseif ns==Ns && ms~=Ms
            k = k+1;
            [X2 X1] = meshgrid((ms-1)*RegionSize+1:ms*RegionSize,(ns-1)*RegionSize+1:N);
            x1 = reshape(X1,1,[]); x2 = reshape(X2,1,[]);
            ImSeg(k).index = sub2ind([M N], x2, x1)';
        else
            k = k+1;
            [X2 X1] = meshgrid((ms-1)*RegionSize+1:M,(ns-1)*RegionSize+1:N);
            x1 = reshape(X1,1,[]); x2 = reshape(X2,1,[]);
            ImSeg(k).index = sub2ind([M N], x2, x1)';
        end
        sMap(ImSeg(k).index) = k;
        ImSeg(k).Npix = length(ImSeg(k).index);
    end
end

%% Initialize mixture proportions 
%  We set same proportion for each superpixel depend on superpixel number.
ws = ones(NN,Ks)/Ks;

%% Initialize the parameters of Nakagami and Gaussian distributions
numax = 1000;
for k=1:Ks   
    % Nakagami distribution for amplitudes: Parameter estimation
    
    % Estimation of scale parameter mu 
       Thetanew = sum(spad(ImSeg(k).index).^2)/ImSeg(k).Npix;
       Theta(k).mu = Thetanew;
     
    % Estimation of shape parameter nu 
      Thetanew = fNakagaminu(spad(ImSeg(k).index),Theta(k).mu,ImSeg(k).Npix,numax);
      Theta(k).nu = Thetanew;
  
end
    
for k=1:Ks
    % Gaussian distribution for coordinates: Parameter estimation

    [sub1 sub2] = ind2sub([M N],ImSeg(k).index);
    sub = [sub1 sub2];

    % Estimation of centroid vector
    Theta(k).centro = mean([sub1 sub2]);
    
    % Estimation of covariance matrix
    dfd = zeros(RegionSize^2,2);
    for l=1:2
        dfd(1:ImSeg(k).Npix,l) = (sub(:,l) -Theta(k).centro(l));
    end
    SCov = dfd'*dfd;
    Theta(k).Sigma = SCov/ImSeg(k).Npix + 0.001*eye(2);
    % The last term regularizes the covariance matrix estimation
    
end

t=0;
w = zeros(NN,Ks);

% Number of iteration required for superpixel convergence 
MaxNIt=20;

%% Starting of iteration
% Pixels are clustered into superpixels according to their amplitude and
% coordinates. For similarity pixel amplitudes are modelled with Nakagami 
% distribution. For proximity pixel coordinates are modelled with Gaussian
% distribution 

while t<MaxNIt
      t=t+1;
    
      %% Posterior of labels
      % **************************
      wa = zeros(NN,Ks);
      wp = zeros(NN,Ks);
    
      for k=1:Ks
          LC = floor(Theta(k).centro);
          [X2 X1] = meshgrid(LC(1)-RegionSize:LC(1)+RegionSize,LC(2)-RegionSize:LC(2)+RegionSize);
          x1 = reshape(X1,1,[]); x2 = reshape(X2,1,[]);
          indnonneg = find(x1>0 & x1<=N );
          x11 = x1(indnonneg); x22 = x2(indnonneg);
          indnonneg = find(x22>0 & x22<=M);
          x111 = x11(indnonneg); x222 = x22(indnonneg);
          LocReg = sub2ind([M N], x222, x111);
          LocPos = [x222' x111'];
                
         % Calculate probabilities from Nakagami density
          wa(LocReg,k) = NakagamiPdf(s(LocReg)',Theta(k).nu,Theta(k).nu/Theta(k).mu);
                
         % Calculate probabilities from Gaussian density
          wp(LocReg,k) = GaussNDPdf(LocPos,Theta(k).centro,Theta(k).Sigma,2);
            
      end
    % Posterior 
      w = ws.*wa.*wp;  

    %% Classification of the pixels into superpixels
    %  ***************************
    %  Instead of full expectation, we use the maximum value of zn
    
      [maxProb ind] = max(w,[],2);
      for k=1:Ks
          ImSeg(k).index = find(ind==k);
          ImSeg(k).Npix = length(ImSeg(k).index);
          sMap(ImSeg(k).index) = k;
      end
    
   
      % Removing empty segments
      [in newset] = find( [ImSeg(1:Ks).Npix] > 0);
      Ks = length(newset);
      ImSeg(1:Ks) = ImSeg(newset);
      Theta(1:Ks) = Theta(newset);
    
    
      %% Estimation of the parameters
      %  **************************
      % Nakagami distribution for amplitudes: Parameter estimation
      for k=1:Ks
        
          % Estimation of scale parameter mu 
          Thetanew = sum(spad(ImSeg(k).index).^2)/ImSeg(k).Npix;
          Theta(k).mu = Thetanew;
        
          % Estimation of shape parameter nu
          Thetanew = fNakagaminu(spad(ImSeg(k).index),Theta(k).mu,ImSeg(k).Npix,numax);
          Theta(k).nu = Thetanew;
           
      end
    
      % Gaussian distribution for coordinates: Parameter estimation
      for k=1:Ks
          [sub1 sub2] = ind2sub([M N],ImSeg(k).index);
          sub = [sub1 sub2];
        
          % Estimation of centroid vector
          Theta(k).centro = mean([sub1 sub2],1);
        
          % Estimation of covariance matrix
          dfd = zeros(RegionSize^2,2);
          
          for l=1:2
              dfd(1:ImSeg(k).Npix,l) = (sub(:,l) -Theta(k).centro(l));
          end

         SCov = dfd'*dfd;
         Theta(k).Sigma = SCov/ImSeg(k).Npix + 0.001*eye(2);
      end

    
      % Calculate mixture proportions of the superpixels
      wk=0;    
      for i=1:Ks
          wk(i) = (ImSeg(i).Npix+alfa-1)/(NN+Ks*(alfa-1)); 
      end
      ws = repmat(wk,NN,1);
end
