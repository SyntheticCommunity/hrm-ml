# hrm_deep_learning_utils.py
# 共享 Python 工具：编码器、数据集、训练函数
# 被各方法 .qmd 文件 import

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset


# ============================================================
# 设备选择（CUDA > MPS > CPU）
# ============================================================
def get_device():
    if torch.cuda.is_available():
        return torch.device('cuda')
    if torch.backends.mps.is_available():
        try:
            torch.zeros(1, device='mps')
            return torch.device('mps')
        except Exception:
            pass
    return torch.device('cpu')


# ============================================================
# 标准化工具
# ============================================================
def fit_scaler(X):
    """用二维数组计算 overall mean/std。X 形状任意。"""
    X = np.asarray(X, dtype=np.float32)
    flat = X.reshape(-1, X.shape[-1])
    mean = flat.mean(axis=0, keepdims=True).astype(np.float32)
    std  = flat.std(axis=0, keepdims=True).astype(np.float32)
    std[std < 1e-6] = 1.0
    return mean, std


def fit_y_scaler(y):
    y = np.asarray(y, dtype=np.float32)
    m = y.mean()
    s = y.std()
    if s < 1e-6: s = 1.0
    return m, s


# ============================================================
# 标准化 PairDataset（样本对）
# ============================================================
class NormalizedPairDataset(Dataset):
    def __init__(self, X, y, x_mean, x_std, y_mean, y_std):
        if isinstance(X, np.ndarray):
            X = torch.tensor(X, dtype=torch.float32)
        if isinstance(y, np.ndarray):
            y = torch.tensor(y, dtype=torch.float32).reshape(-1, 1)
        self.x1 = (X[:, 0, :] - torch.tensor(x_mean)) / torch.tensor(x_std)
        self.x2 = (X[:, 1, :] - torch.tensor(x_mean)) / torch.tensor(x_std)
        self.y  = (y - y_mean) / y_std

    def __len__(self): return len(self.y)
    def __getitem__(self, i): return self.x1[i], self.x2[i], self.y[i]


# ============================================================
# 标准化 TripletDataset
# ============================================================
class TripletDataset(Dataset):
    def __init__(self, triplets, hrm_data, x_mean, x_std):
        if isinstance(hrm_data, np.ndarray):
            hrm_data = torch.tensor(hrm_data, dtype=torch.float32)
        x_mean = torch.tensor(x_mean)
        x_std  = torch.tensor(x_std)
        self.hrm = (hrm_data - x_mean) / x_std
        self.triplets = triplets

    def __len__(self): return len(self.triplets)
    def __getitem__(self, i):
        a, p, n = self.triplets[i]
        return self.hrm[a], self.hrm[p], self.hrm[n]


# ============================================================
# 评估与预测
# ============================================================
@torch.no_grad()
def evaluate_regression(model, dataset, device, batch_size=256):
    model.eval()
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False)
    crit = nn.MSELoss()
    total, n = 0.0, 0
    for x1_b, x2_b, y_b in loader:
        x1_b = x1_b.to(device); x2_b = x2_b.to(device); y_b = y_b.to(device)
        total += crit(model(x1_b, x2_b), y_b).item() * x1_b.size(0)
        n += x1_b.size(0)
    return total / n


@torch.no_grad()
def predict_all(model, dataset, device, batch_size=256):
    model.eval()
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False)
    preds = []
    for x1_b, x2_b, _ in loader:
        x1_b = x1_b.to(device); x2_b = x2_b.to(device)
        preds.append(model(x1_b, x2_b).cpu().numpy())
    return np.concatenate(preds).flatten()


@torch.no_grad()
def encode_all(encoder, hrm_data, x_mean, x_std, device=None, batch_size=256):
    if device is None: device = get_device()
    encoder = encoder.to(device)
    encoder.eval()
    if isinstance(hrm_data, np.ndarray):
        hrm_data = torch.tensor(hrm_data, dtype=torch.float32)
    x_mean = torch.tensor(x_mean)
    x_std  = torch.tensor(x_std)
    hrm_norm = (hrm_data - x_mean) / x_std
    ds = torch.utils.data.TensorDataset(hrm_norm)
    loader = DataLoader(ds, batch_size=batch_size, shuffle=False)
    embs = []
    for (x,) in loader:
        embs.append(encoder(x.to(device)).cpu().numpy())
    return np.concatenate(embs)


# ============================================================
# 通用回归训练（CosineAnnealingWarmRestarts + AdamW）
# ============================================================
def train_regression_model(model, train_dataset, val_dataset,
                           device=None, epochs=300, lr=1e-3,
                           batch_size=256, patience=40):
    if device is None: device = get_device()
    model = model.to(device)
    loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-3)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
        optimizer, T_0=30, T_mult=2, eta_min=lr * 0.01)
    criterion = nn.MSELoss()

    best_loss = float('inf')
    best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
    patience_counter = 0
    train_losses, val_losses = [], []

    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for x1_b, x2_b, y_b in loader:
            x1_b = x1_b.to(device); x2_b = x2_b.to(device); y_b = y_b.to(device)
            optimizer.zero_grad()
            loss = criterion(model(x1_b, x2_b), y_b)
            if torch.isnan(loss) or torch.isinf(loss): continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            epoch_loss += loss.item() * x1_b.size(0)
        train_losses.append(epoch_loss / len(train_dataset))

        val_loss = evaluate_regression(model, val_dataset, device)
        val_losses.append(val_loss)
        scheduler.step(epoch + 1)

        if np.isnan(val_loss):
            model.load_state_dict(best_state); break
        if val_loss < best_loss:
            best_loss = val_loss
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            patience_counter = 0
        else:
            patience_counter += 1
        if patience_counter >= patience: break

    model.load_state_dict(best_state)
    return model, train_losses, val_losses, epoch - patience_counter + 1


# ============================================================
# Triplet 训练
# ============================================================
@torch.no_grad()
def evaluate_triplet(model, dataset, device, batch_size=64):
    model.eval()
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False)
    total, n = 0.0, 0
    for a_b, p_b, n_b in loader:
        a_b = a_b.to(device); p_b = p_b.to(device); n_b = n_b.to(device)
        loss, _, _ = model(a_b, p_b, n_b)
        total += loss.item() * a_b.size(0); n += a_b.size(0)
    return total / n


def train_triplet_model(model, train_dataset, val_dataset,
                        device=None, epochs=200, lr=1e-3,
                        batch_size=64, patience=40):
    if device is None: device = get_device()
    model = model.to(device)
    loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-3)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
        optimizer, T_0=30, T_mult=2, eta_min=lr * 0.01)

    best_loss = float('inf')
    best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
    patience_counter = 0
    train_losses, val_losses = [], []

    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for a_b, p_b, n_b in loader:
            a_b = a_b.to(device); p_b = p_b.to(device); n_b = n_b.to(device)
            optimizer.zero_grad()
            loss, _, _ = model(a_b, p_b, n_b)
            if torch.isnan(loss) or torch.isinf(loss): continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            epoch_loss += loss.item() * a_b.size(0)
        train_losses.append(epoch_loss / len(train_dataset))

        val_loss = evaluate_triplet(model, val_dataset, device)
        val_losses.append(val_loss)
        scheduler.step(epoch + 1)

        if np.isnan(val_loss):
            model.load_state_dict(best_state); break
        if val_loss < best_loss:
            best_loss = val_loss
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            patience_counter = 0
        else:
            patience_counter += 1
        if patience_counter >= patience: break

    model.load_state_dict(best_state)
    return model, train_losses, val_losses, epoch - patience_counter + 1


# ============================================================
# 距离矩阵工具
# ============================================================
def build_pred_dist_matrix(pair_indices_py, pred_values, n_samples):
    mat = np.zeros((n_samples, n_samples))
    for k in range(len(pred_values)):
        i, j = pair_indices_py[0, k], pair_indices_py[1, k]
        mat[i, j] = mat[j, i] = pred_values[k]
    return mat
